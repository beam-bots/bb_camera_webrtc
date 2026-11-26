# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Camera.WebRTC do
  @moduledoc """
  Streams a Beam Bots camera to browsers over WebRTC, encoding it once however
  many are watching.

      signaling = Membrane.WebRTC.Signaling.new()
      {:ok, ref} = BB.Camera.WebRTC.watch(MyRobot, :eye, signaling)

  The browser is the other peer on `signaling`; see "In the browser" below.
  The stream runs until the calling process exits.

  ## One encode per camera

  The first viewer of a camera starts a pipeline for it -
  `BB.Camera.Membrane.Source`, an H.264 encoder, and a sink for each viewer -
  and the last viewer to leave stops it, which releases the camera. Everyone
  in between shares the one encoder, so a second viewer costs the network, not
  the CPU.

  The encoder is libx264 tuned for latency rather than size: the `ultrafast`
  preset, `zerolatency` tuning, the baseline profile with no B-frames, and a
  keyframe every 30 frames. A viewer joining mid-stream asks for a keyframe and
  gets one straight away; the keyframe interval bounds the wait regardless.
  libx264 runs on the CPU, which on a Raspberry Pi 4 or 5 is close to a core
  for 640x480 at 30fps.

  ## When the stream ends

  `watch/4` returns a reference, and the stream has ended - the camera stopped
  or restarted, the browser's connection failed, or the pipeline went down -
  when the caller receives either

    * `{BB.Camera.WebRTC, ref, :ended}`, or
    * `{:DOWN, ref, :process, pid, reason}`, since `ref` also monitors the
      camera's pipeline.

  Either way, start again with a new signaling and another `watch/4`.

  ## Networks

  By default no STUN or TURN servers are used, so the browser has to be able to
  reach the robot directly - right for a robot on the same network, Tailscale
  included. A browser behind NAT, such as on a mobile connection, needs a TURN
  server; pass it as `:ice_servers`.

  ## In the browser

  `assets/player.js` in this package is a Phoenix LiveView hook that plays the
  stream in a `<video>` element; bundle it with your own assets.
  """

  alias BB.Camera.WebRTC.Pipeline

  @registry BB.Camera.WebRTC.Registry
  @supervisor BB.Camera.WebRTC.Supervisor

  @options_schema Spark.Options.new!(
                    ice_servers: [
                      type: {:list, :map},
                      default: [],
                      doc:
                        "`ExWebRTC` ICE servers, e.g. `[%{urls: \"turn:turn.example.com\", username: ..., credential: ...}]`. None by default, for a browser on the robot's network."
                    ]
                  )

  @doc """
  Streams `camera` on `robot` to the peer on `signaling` until the calling
  process exits.

  ## Options

  #{Spark.Options.docs(@options_schema)}
  """
  @spec watch(module(), atom(), Membrane.WebRTC.Signaling.t(), keyword()) ::
          {:ok, reference()} | {:error, term()}
  def watch(robot, camera, signaling, opts \\ []) do
    with {:ok, opts} <- Spark.Options.validate(opts, @options_schema),
         {:ok, pipeline} <- pipeline(robot, camera) do
      ref = Process.monitor(pipeline)
      send(pipeline, {:add_viewer, self(), ref, signaling, opts[:ice_servers]})
      {:ok, ref}
    end
  end

  # Two viewers arriving at once both try to start it; the registry lets one
  # win and tells the other which pipeline did.
  defp pipeline(robot, camera) do
    name = {:via, Registry, {@registry, {robot, camera}}}

    child = %{
      id: {robot, camera},
      start:
        {Membrane.Pipeline, :start_link, [Pipeline, [robot: robot, camera: camera], [name: name]]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(@supervisor, child) do
      {:ok, _supervisor, pipeline} -> {:ok, pipeline}
      {:error, {:already_started, pipeline}} -> {:ok, pipeline}
      {:error, reason} -> {:error, reason}
    end
  end
end
