# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Camera.WebRTC.TestRobot do
  @moduledoc false
  use BB

  settings do
    name(:bb_camera_webrtc_test)
  end

  topology do
    link :base do
      sensor(:eye, {BB.Camera.Synthetic, width: 160, height: 120, clock: {:rate, 30}})
    end
  end
end
