<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# AGENTS.md

Guidance for coding assistants working on `bb_camera_webrtc`.

## What this package is

`BB.Camera.WebRTC.watch/4` streams a Beam Bots camera to a browser over
WebRTC. One Membrane pipeline per camera
(`BB.Camera.WebRTC.Pipeline`), started by the first viewer and stopped by the
last, registered in `BB.Camera.WebRTC.Registry` under `{robot, camera}` and
supervised by `BB.Camera.WebRTC.Supervisor` — both started by this package's
application. `assets/player.js` is the browser half.

It does not own any UI: `bb_liveview` (and later `bb_kino`) do.

## Build and test

```bash
BB_VERSION=local mix check --no-retry
BB_VERSION=local mix test
```

The tests stream to a real WebRTC peer — `BB.Camera.WebRTC.Test.Browser`, an
`ExWebRTC.PeerConnection` playing the browser — and wait for RTP to arrive.
No browser and no camera hardware is needed.

## Design decisions worth not re-litigating

- **Cameras know nothing about WebRTC.** The pipeline reads the camera through
  `BB.Camera.Membrane.Source`, like any other consumer of the hub. There was a
  design in which each camera ran its own WebRTC pipeline per viewer (Lars
  Wikman's `BB.LiveView.VideoSource`, on his `bb_liveview` branch); it put an
  encoder per viewer inside every driver. Don't move transport into drivers.
- **One encode per camera.** A `Membrane.Tee` after the parser gives each
  viewer its own `Membrane.WebRTC.Sink`. A joining viewer's sink asks for a
  keyframe when the browser does, and the request travels upstream through the
  tee and parser to the encoder; `gop_size: 30` bounds the wait regardless.
- **One viewer's failure is one viewer's.** Each sink is in its own crash
  group, so a browser whose connection fails takes down only its own branch.
- **The pipeline stops with its last viewer**, which releases the camera, and
  ends - telling every viewer - when the camera's stream does. A viewer joining
  a pipeline on its way out gets `:DOWN` at once; the contract is that it then
  watches again, which starts a fresh pipeline. Don't try to close that window
  from inside: answering it in the viewer is simpler and always right.
- **libx264, latency over size.** `ultrafast`, `zerolatency`, baseline profile,
  no B-frames, keyframe every 30 frames. libx264 has no
  `:constrained_baseline` profile; `:baseline` with no B-frames is the same
  thing. Frames are full-range I420, so the stream is flagged
  `color_range: pc`; unflagged, browsers crush the blacks and whites.
- **No ICE servers by default.** For a robot on the browser's network. TURN is
  a deployment concern, passed in as `:ice_servers`.
- **Our own browser hook.** membrane_webrtc_plugin's `createPlayerHook` (0.26)
  assigns messages to an undeclared variable, which throws in an ES module, so
  neither the SDP answer nor any candidate reaches the server.

## Not yet

- **Hardware encoding.** The Raspberry Pi 4 has an H.264 encoder (V4L2 M2M,
  ffmpeg's `h264_v4l2m2m`); `membrane_h264_ffmpeg_plugin` always uses
  libx264, so it needs an element of its own.
- **Adaptive bitrate.** WebRTC done properly adjusts the encoder to the
  network. That matters for driving over a mobile connection.

## Licensing headers

Every source file carries an SPDX header — `#` for Elixir, `//` for
JavaScript, an HTML comment for Markdown, a `<file>.license` sidecar for
binaries. `mix check` runs `reuse lint`. A new file credits the user you're
working for, from `git config user.name`, with the current year.
