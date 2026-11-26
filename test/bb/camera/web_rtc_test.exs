# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Camera.WebRTCTest do
  # The robot and the pipeline registry are global, so these run one at a time.
  use ExUnit.Case, async: false

  alias BB.Camera.WebRTC
  alias BB.Camera.WebRTC.Test.Browser
  alias BB.Camera.WebRTC.TestRobot

  # An upper bound on events that must happen - ICE, DTLS and the first
  # keyframe - not a guess at how long they take.
  @connected 15_000

  # Started after the robot so that they stop before it: each test's
  # pipelines are shut down with the test, while their camera still exists.
  setup do
    start_supervised!(TestRobot)
    start_supervised!({Registry, keys: :unique, name: WebRTC.Registry})
    start_supervised!({DynamicSupervisor, name: WebRTC.Supervisor, strategy: :one_for_one})
    :ok
  end

  defp browser do
    {:ok, browser} = Browser.start(self())
    on_exit(fn -> Process.exit(browser, :kill) end)
    browser
  end

  defp pipeline do
    [{pipeline, _value}] = Registry.lookup(WebRTC.Registry, {TestRobot, :eye})
    pipeline
  end

  # A viewer learns either way: `:ended` from the pipeline, or its `:DOWN`.
  defp assert_stream_ended(viewer) do
    receive do
      {:ended, ^viewer} -> :ok
      {:pipeline_down, ^viewer, _reason} -> :ok
    after
      @connected -> flunk("#{inspect(viewer)} was never told its stream ended")
    end
  end

  test "streams the camera to a WebRTC peer as H.264" do
    browser = browser()
    assert {:ok, _ref} = Browser.watch(browser, TestRobot, :eye)

    assert_receive {:rtp, ^browser, _payload_type}, @connected
  end

  test "viewers of one camera share one pipeline" do
    first = browser()
    second = browser()

    {:ok, _ref} = Browser.watch(first, TestRobot, :eye)
    {:ok, _ref} = Browser.watch(second, TestRobot, :eye)

    assert_receive {:rtp, ^first, _}, @connected
    assert_receive {:rtp, ^second, _}, @connected
    assert [_one] = Registry.lookup(WebRTC.Registry, {TestRobot, :eye})
  end

  test "a viewer leaving doesn't stop the others" do
    staying = browser()
    leaving = browser()

    {:ok, _ref} = Browser.watch(staying, TestRobot, :eye)
    {:ok, _ref} = Browser.watch(leaving, TestRobot, :eye)
    assert_receive {:rtp, ^leaving, _}, @connected
    shared = pipeline()

    Process.exit(leaving, :kill)

    # Whenever the pipeline sees the exit, `staying` is still watching, so a
    # newcomer joins the same pipeline and is streamed to.
    joining = browser()
    {:ok, _ref} = Browser.watch(joining, TestRobot, :eye)
    assert_receive {:rtp, ^joining, _}, @connected
    assert pipeline() == shared
  end

  test "the last viewer leaving stops the pipeline, releasing the camera" do
    viewer = browser()
    {:ok, _ref} = Browser.watch(viewer, TestRobot, :eye)
    assert_receive {:rtp, ^viewer, _}, @connected

    monitor = Process.monitor(pipeline())
    Process.exit(viewer, :kill)

    assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, @connected
  end

  test "unwatching the last viewer stops the pipeline, and nothing more arrives about it" do
    viewer = browser()
    {:ok, ref} = Browser.watch(viewer, TestRobot, :eye)
    assert_receive {:rtp, ^viewer, _}, @connected
    monitor = Process.monitor(pipeline())

    assert :ok = Browser.unwatch(viewer, TestRobot, :eye, ref)

    assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, @connected
    # The viewer has handled everything sent to it before this returns.
    :sys.get_state(viewer)
    refute_received {:ended, ^viewer}
    refute_received {:pipeline_down, ^viewer, _reason}
  end

  test "unwatching one viewer doesn't stop the others" do
    staying = browser()
    leaving = browser()

    {:ok, _ref} = Browser.watch(staying, TestRobot, :eye)
    {:ok, ref} = Browser.watch(leaving, TestRobot, :eye)
    assert_receive {:rtp, ^leaving, _}, @connected
    shared = pipeline()

    assert :ok = Browser.unwatch(leaving, TestRobot, :eye, ref)

    joining = browser()
    {:ok, _ref} = Browser.watch(joining, TestRobot, :eye)
    assert_receive {:rtp, ^joining, _}, @connected
    assert pipeline() == shared
  end

  test "unwatching a stream that has already ended is fine" do
    viewer = browser()
    {:ok, ref} = Browser.watch(viewer, TestRobot, :eye)
    assert_receive {:rtp, ^viewer, _}, @connected

    stop_supervised!(TestRobot)
    assert_stream_ended(viewer)

    assert :ok = Browser.unwatch(viewer, TestRobot, :eye, ref)
  end

  test "viewers are told when the camera goes away" do
    viewer = browser()
    {:ok, _ref} = Browser.watch(viewer, TestRobot, :eye)
    assert_receive {:rtp, ^viewer, _}, @connected

    stop_supervised!(TestRobot)

    assert_stream_ended(viewer)
  end
end
