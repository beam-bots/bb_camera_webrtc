// SPDX-FileCopyrightText: 2026 James Harton
// SPDX-License-Identifier: Apache-2.0

// A Phoenix LiveView hook that plays a `BB.Camera.WebRTC` stream in a <video>.
//
// The server side relays signaling between this hook and the camera's
// `Membrane.WebRTC.Sink`, registered on the `Membrane.WebRTC.Signaling` passed
// to `BB.Camera.WebRTC.watch/4` with `message_format: :json_data`:
//
//   * it pushes the sink's messages to this element as
//     `webrtc_signaling-<element id>` events, and
//   * it receives this element's messages as `webrtc_signaling` events.
//
// Bundle it with your own assets:
//
//   import { createPlayerHook } from "../../deps/bb_camera_webrtc/assets/player.js";
//   const Hooks = { CameraPlayer: createPlayerHook() };
//
// No ICE servers by default: the browser reaches the robot directly. Pass the
// same TURN servers given to `watch/4` when it can't.
//
// Derived from `createPlayerHook` in membrane_webrtc_plugin, which assigns its
// messages to an undeclared variable - a ReferenceError in an ES module, so
// neither the answer nor any candidate ever reached the server.
export function createPlayerHook(iceServers = []) {
  return {
    mounted() {
      this.pc = new RTCPeerConnection({ iceServers });

      // Attached when the first track arrives rather than as an empty stream up
      // front: the element autoplays, and replacing a stream it has started
      // loading aborts that load, which browsers report as an uncaught error.
      this.pc.ontrack = ({ track }) => {
        if (this.el.srcObject) {
          this.el.srcObject.addTrack(track);
        } else {
          this.el.srcObject = new MediaStream([track]);
        }
      };

      this.pc.onicecandidate = ({ candidate }) => {
        this.pushEventTo(this.el, "webrtc_signaling", { type: "ice_candidate", data: candidate });
      };

      this.pc.onconnectionstatechange = () => {
        this.el.dataset.connectionState = this.pc.connectionState;
      };

      this.handleEvent(`webrtc_signaling-${this.el.id}`, async ({ type, data }) => {
        switch (type) {
          case "sdp_offer": {
            await this.pc.setRemoteDescription(data);
            const answer = await this.pc.createAnswer();
            await this.pc.setLocalDescription(answer);
            this.pushEventTo(this.el, "webrtc_signaling", { type: "sdp_answer", data: answer });
            break;
          }
          case "ice_candidate":
            await this.pc.addIceCandidate(data);
            break;
        }
      });
    },

    destroyed() {
      this.pc?.close();
    },
  };
}
