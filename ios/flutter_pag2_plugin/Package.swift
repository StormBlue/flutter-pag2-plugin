// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_pag2_plugin",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "flutter-pag2-plugin", targets: ["flutter_pag2_plugin"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/libpag/pag-ios.git", from: "4.5.41")
    ],
    targets: [
        .target(
            name: "flutter_pag2_plugin",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "libpag", package: "pag-ios")
            ]
        )
    ]
)
