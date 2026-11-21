// swift-tools-version: 5.7

import PackageDescription

let package = Package(
  name: "homebrew-autoupdate",
  platforms: [
    .macOS(.v11),
  ],
  products: [
    .executable(
      name: "brew-autoupdate",
      targets: ["BrewAutoupdate"]
    ),
  ],
  targets: [
    .executableTarget(
      name: "BrewAutoupdate",
      path: "app",
      exclude: [
        "README.md",
        "applet.icns",
        "brew-autoupdate.app",
        "build.sh",
        "notify-result.sh",
      ],
      sources: ["BrewAutoupdate.swift"]
    ),
  ]
)
