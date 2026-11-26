# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Camera.WebRTC.MixProject do
  use Mix.Project

  @moduledoc """
  WebRTC streaming of Beam Bots cameras to browsers, encoded once per camera.
  """

  @version "0.1.0"

  def project do
    [
      aliases: aliases(),
      app: :bb_camera_webrtc,
      consolidate_protocols: Mix.env() == :prod,
      deps: deps(),
      description: @moduledoc,
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix]
    ]
  end

  defp package do
    [
      files: ~w(lib assets .formatter.exs mix.exs README* CHANGELOG* LICENSE* usage-rules.md),
      maintainers: ["James Harton <james@harton.nz>"],
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => "https://github.com/beam-bots/bb_camera_webrtc",
        "Sponsor" => "https://github.com/sponsors/jimsynz"
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BB.Camera.WebRTC.Application, []}
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.png",
      extras:
        ["README.md", "CHANGELOG.md"]
        |> Enum.concat(Path.wildcard("documentation/**/*.{md,livemd,cheatmd}")),
      groups_for_extras: [
        Tutorials: ~r/tutorials\//
      ],
      source_ref: "main",
      source_url: "https://github.com/beam-bots/bb_camera_webrtc"
    ]
  end

  defp aliases, do: []

  defp bb_dep(default, package \\ :bb) do
    case System.get_env("BB_VERSION") do
      nil -> default
      "local" -> [path: "../#{package}", override: true]
      "main" -> [git: "https://github.com/beam-bots/#{package}.git", override: true]
      version -> "~> #{version}"
    end
  end

  defp deps do
    [
      {:bb, bb_dep("~> 0.33")},
      {:bb_camera, bb_dep("~> 0.2", :bb_camera)},
      {:membrane_core, "~> 1.3"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.32"},
      {:membrane_h26x_plugin, "~> 0.10"},
      {:membrane_webrtc_plugin, "~> 0.26"},

      # Membrane's `ratio` still declares `decimal ~> 1.6 or ~> 2.0`, which would
      # hold this package's own dev/test tree down on a `decimal` with open DoS
      # advisories. `ratio` treats `decimal` as optional, so overriding is safe.
      # Mix only honours `override: true` from the top-level project, so a robot
      # depending on this package needs the same line in its own `mix.exs`.
      {:decimal, "~> 3.0", override: true, only: [:dev, :test]},

      # dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: [:dev], runtime: false}
    ]
  end

  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
