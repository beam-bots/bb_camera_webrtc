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

  setup do
    # A pipeline outlives its test briefly, ending once its viewers and robot
    # have. Joining one on its way out ends the stream at once - which a real
    # viewer answers by watching again - so each test starts once the last
    # one's pipeline is gone.
    await_no_pipeline()
    start_supervised!(TestRobot)
    :ok
  end

  defp await_no_pipeline do
    case Registry.lookup(BB.Camera.WebRTC.Registry, {TestRobot, :eye}) do
      [] ->
        :ok

      [{pipeline, _value}] ->
        monitor = Process.monitor(pipeline)
        assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, @connected
    end
  end

  defp browser do
    {:ok, browser} = Browser.start(self())
    on_exit(fn -> Process.exit(browser, :kill) end)
    browser
  end

  defp pipeline do
    [{pipeline, _value}] = Registry.lookup(BB.Camera.WebRTC.Registry, {TestRobot, :eye})
    pipeline
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
    assert [_one] = Registry.lookup(BB.Camera.WebRTC.Registry, {TestRobot, :eye})
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

  test "viewers are told when the camera goes away" do
    viewer = browser()
    {:ok, _ref} = Browser.watch(viewer, TestRobot, :eye)
    assert_receive {:rtp, ^viewer, _}, @connected

    stop_supervised!(TestRobot)

    assert_receive {ended, ^viewer, _reason_or_nothing} when ended in [:ended, :pipeline_down],
                   @connected
  end
end
