<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# bb_camera_webrtc usage rules

`bb_camera_webrtc` streams Beam Bots cameras to browsers over WebRTC. For
cameras themselves — drivers, the hub, frames — see `bb_camera`'s rules. This
file covers only streaming.

## Core principles

1. **Watch from the process that owns the viewer.** The stream lasts until the
   caller of `watch/4` exits; for a LiveView, call it from the LiveView.
2. **Handle the end of a stream by watching again.** `{BB.Camera.WebRTC, ref,
   :ended}` or `{:DOWN, ref, ...}` both mean it, with a new signaling.
3. **Never encode a camera yourself for a second viewer.** Call `watch/4`
   again; the camera's one encoder is shared.

## Wiring it in

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    signaling = Membrane.WebRTC.Signaling.new()
    :ok = Membrane.WebRTC.Signaling.register_peer(signaling, message_format: :json_data)
    {:ok, ref} = BB.Camera.WebRTC.watch(MyRobot, :eye, signaling)
    {:ok, assign(socket, signaling: signaling, watch: ref)}
  else
    {:ok, socket}
  end
end

# The sink's messages, to the browser.
def handle_info({:membrane_webrtc_signaling, _pid, message, _meta}, socket) do
  {:noreply, push_event(socket, "webrtc_signaling-player", message)}
end

# The browser's, to the sink.
def handle_event("webrtc_signaling", message, socket) do
  Membrane.WebRTC.Signaling.signal(socket.assigns.signaling, message)
  {:noreply, socket}
end
```

with `<video id="player" phx-hook="CameraPlayer" autoplay muted playsinline>`
and `assets/player.js` bundled as the `CameraPlayer` hook.

## Options

| Option | Default | |
|---|---|---|
| `:ice_servers` | `[]` | STUN/TURN servers for browsers that can't reach the robot directly |

## Anti-patterns

- **Calling `watch/4` from a short-lived process.** The stream stops when it
  exits.
- **Ignoring `:ended`.** The video freezes on its last frame and stays there.
- **Using membrane_webrtc_plugin's own `createPlayerHook`** (0.26). It throws
  in an ES module before the connection can complete.

## Further reading

- [bb_camera_webrtc docs](https://hexdocs.pm/bb_camera_webrtc)
- `BB.Camera.WebRTC` for the pipeline, the encoder settings and networks
