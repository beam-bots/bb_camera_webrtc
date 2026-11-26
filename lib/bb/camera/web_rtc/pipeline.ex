# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Camera.WebRTC.Pipeline do
  @moduledoc false
  # One camera, encoded once, sent to every viewer.
  #
  #   camera -> encoder -> parser -> tee -+-> sink (viewer 1)
  #                                       +-> sink (viewer 2) ...
  #
  # Viewers arrive as `{:add_viewer, pid, ref, signaling, ice_servers}` from
  # `BB.Camera.WebRTC.watch/4`. Each gets its own branch off the tee in its own
  # crash group, so one browser's failed connection takes down only its own
  # sink. The pipeline monitors viewers, drops a viewer's branch when it goes
  # or unwatches, and stops when the last one has, which releases the camera.

  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      child(:camera, %BB.Camera.Membrane.Source{
        robot: Keyword.fetch!(opts, :robot),
        camera: Keyword.fetch!(opts, :camera)
      })
      |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{
        preset: :ultrafast,
        tune: :zerolatency,
        # libx264 has no :constrained_baseline; :baseline with no B-frames is
        # the same thing, and it is what every browser decodes.
        profile: :baseline,
        max_b_frames: 0,
        gop_size: 30,
        # Camera frames are full-range I420. Unflagged, browsers read them as
        # limited range and crush the blacks and whites.
        ffmpeg_params: %{"color_range" => "pc"}
      })
      |> child(:parser, %Membrane.H264.Parser{output_alignment: :nalu})
      |> child(:tee, Membrane.Tee)

    {[spec: spec], %{viewers: %{}}}
  end

  @impl true
  def handle_info({:add_viewer, pid, ref, signaling, ice_servers}, _ctx, state) do
    monitor = Process.monitor(pid)

    branch =
      get_child(:tee)
      |> via_out(Pad.ref(:output, ref))
      |> via_in(:input, options: [kind: :video])
      |> child({:sink, ref}, %Membrane.WebRTC.Sink{
        signaling: signaling,
        tracks: [:video],
        video_codec: :h264,
        ice_servers: ice_servers
      })

    viewer = %{pid: pid, monitor: monitor}

    {[spec: {branch, group: {:viewer, ref}, crash_group_mode: :temporary}],
     put_in(state.viewers[ref], viewer)}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, _ctx, state) do
    case Enum.find(state.viewers, fn {_ref, viewer} -> viewer.monitor == monitor end) do
      nil -> {[], state}
      {ref, _viewer} -> leave(ref, [remove_children: {:sink, ref}], state)
    end
  end

  def handle_info(_message, _ctx, state), do: {[], state}

  # Synchronous so that anything sent to the viewer before the reply - an
  # `:ended` from its connection failing - is already in its mailbox for
  # `BB.Camera.WebRTC.unwatch/3` to flush.
  @impl true
  def handle_call({:remove_viewer, ref}, _ctx, state) do
    case Map.fetch(state.viewers, ref) do
      {:ok, viewer} ->
        Process.demonitor(viewer.monitor, [:flush])
        leave(ref, [reply: :ok, remove_children: {:sink, ref}], state)

      :error ->
        {[reply: :ok], state}
    end
  end

  # The browser's connection failed, or its sink did; the rest carry on.
  @impl true
  def handle_crash_group_down({:viewer, ref}, _ctx, state) do
    case Map.fetch(state.viewers, ref) do
      {:ok, viewer} ->
        Process.demonitor(viewer.monitor, [:flush])
        send(viewer.pid, {BB.Camera.WebRTC, ref, :ended})
        leave(ref, [], state)

      :error ->
        {[], state}
    end
  end

  # The camera has stopped - its capture ended, or its robot went down - so
  # every stream has ended. Viewers start again, which starts a new pipeline.
  @impl true
  def handle_element_end_of_stream(:tee, :input, _ctx, state) do
    for {ref, viewer} <- state.viewers, do: send(viewer.pid, {BB.Camera.WebRTC, ref, :ended})
    {[terminate: :normal], %{state | viewers: %{}}}
  end

  def handle_element_end_of_stream(_element, _pad, _ctx, state), do: {[], state}

  defp leave(ref, actions, state) do
    state = %{state | viewers: Map.delete(state.viewers, ref)}

    if state.viewers == %{} do
      {actions ++ [terminate: :normal], state}
    else
      {actions, state}
    end
  end
end
