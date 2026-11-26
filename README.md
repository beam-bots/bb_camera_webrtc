<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

<img src="https://github.com/beam-bots/bb/blob/main/logos/beam_bots_logo.png?raw=true" alt="Beam Bots Logo" width="250" />

# bb_camera_webrtc

[![CI](https://github.com/beam-bots/bb_camera_webrtc/actions/workflows/ci.yml/badge.svg)](https://github.com/beam-bots/bb_camera_webrtc/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache--2.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![Hex version badge](https://img.shields.io/hexpm/v/bb_camera_webrtc.svg)](https://hex.pm/packages/bb_camera_webrtc)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/bb_camera_webrtc)
[![REUSE status](https://api.reuse.software/badge/github.com/beam-bots/bb_camera_webrtc)](https://api.reuse.software/info/github.com/beam-bots/bb_camera_webrtc)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/beam-bots/bb_camera_webrtc)

Streams [Beam Bots](https://github.com/beam-bots/bb) cameras to browsers over
WebRTC, encoding each camera once however many people are watching. It is what
[`bb_liveview`](https://github.com/beam-bots/bb_liveview) uses for its camera
previews, and the piece to reach for if you are putting a camera in a web page
of your own.

```elixir
signaling = Membrane.WebRTC.Signaling.new()
{:ok, ref} = BB.Camera.WebRTC.watch(MyRobot, :eye, signaling)
```

## How it works

The first viewer of a camera starts a [Membrane](https://membrane.stream)
pipeline for it — the camera's raw frames from `BB.Camera.Membrane.Source`, an
H.264 encoder tuned for latency, and a WebRTC sink per viewer — and the last
viewer to leave stops it, which releases the camera. A second viewer costs
network, not CPU.

Measured over Tailscale at 640x480 and 30fps, from a frame being made on the
robot to it being shown in the browser: 68ms median, 66–69ms in all. That is a
best case — the test frames were flat and compress to nothing — but it is the
pipeline's own cost: a real camera adds its sensor's delay, and a real scene
takes longer to encode and send.

## Requirements

- **`bb_camera`**, and a camera driver delivering raw frames.
- **The encoder runs on the CPU.** libx264 at 640x480 and 30fps took about a
  fifth of a laptop core; on a Raspberry Pi 4 or 5 expect most of one.
- **Network.** No STUN or TURN servers are used by default, so the browser has
  to reach the robot directly: the same network, or a VPN such as Tailscale.
  A browser behind NAT — on a mobile connection, say — needs a TURN server,
  passed as `:ice_servers`.

## Installation

```elixir
def deps do
  [
    {:bb_camera_webrtc, "~> 0.1.0"},

    # Membrane's `ratio` pins `decimal` below what `bb` wants, and below the
    # versions that fix its DoS advisories. `ratio` treats `decimal` as
    # optional, so overriding is safe. Mix only honours this from your own
    # `mix.exs`.
    {:decimal, "~> 3.0", override: true}
  ]
end
```

## In the browser

`assets/player.js` is a Phoenix LiveView hook that plays the stream in a
`<video>` element. Bundle it with your own assets:

```javascript
import { createPlayerHook } from "../../deps/bb_camera_webrtc/assets/player.js";
const Hooks = { CameraPlayer: createPlayerHook() };
```

## Licence

Apache 2.0. See [LICENSES](LICENSES).
