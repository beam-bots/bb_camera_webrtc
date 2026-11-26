# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Camera.WebRTC.Test.Browser do
  @moduledoc false
  # Plays the browser's part from a test: answers the sink's offer with an
  # `ExWebRTC.PeerConnection`, trades ICE candidates, and reports the RTP it
  # receives to the process that started it.
  #
  # A process of its own, so a test can run several and stop one by exiting
  # it, exactly as a browser tab going away stops a LiveView.

  use GenServer

  alias BB.Camera.WebRTC
  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Membrane.WebRTC.Signaling

  def start(report_to) do
    GenServer.start(__MODULE__, report_to)
  end

  @doc "Watch `camera` from the browser's own process, as a LiveView would."
  def watch(browser, robot, camera), do: GenServer.call(browser, {:watch, robot, camera})

  @impl true
  def init(report_to) do
    {:ok, pc} = PeerConnection.start_link(ice_servers: [])
    signaling = Signaling.new()
    :ok = Signaling.register_peer(signaling)
    {:ok, %{pc: pc, signaling: signaling, report_to: report_to, reported?: false}}
  end

  @impl true
  def handle_call({:watch, robot, camera}, _from, state) do
    {:reply, WebRTC.watch(robot, camera, state.signaling), state}
  end

  @impl true
  def handle_info({:membrane_webrtc_signaling, _pid, %SessionDescription{} = offer, _meta}, state) do
    :ok = PeerConnection.set_remote_description(state.pc, offer)
    {:ok, answer} = PeerConnection.create_answer(state.pc)
    :ok = PeerConnection.set_local_description(state.pc, answer)
    Signaling.signal(state.signaling, answer)
    {:noreply, state}
  end

  def handle_info({:membrane_webrtc_signaling, _pid, %ICECandidate{} = candidate, _meta}, state) do
    PeerConnection.add_ice_candidate(state.pc, candidate)
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    Signaling.signal(state.signaling, candidate)
    {:noreply, state}
  end

  # One report is enough to prove video is flowing; more would flood the test.
  def handle_info({:ex_webrtc, _pc, {:rtp, _track, _rid, packet}}, %{reported?: false} = state) do
    send(state.report_to, {:rtp, self(), packet.payload_type})
    {:noreply, %{state | reported?: true}}
  end

  def handle_info({WebRTC, _ref, :ended}, state) do
    send(state.report_to, {:ended, self()})
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    send(state.report_to, {:pipeline_down, self(), reason})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
