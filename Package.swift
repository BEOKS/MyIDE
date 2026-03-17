// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MyIDE",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MyIDECore",
            targets: ["MyIDECore"]
        ),
        .executable(
            name: "MyIDESampleMacApp",
            targets: ["MyIDESampleMacApp"]
        ),
        .executable(
            name: "MyIDECLI",
            targets: ["MyIDECLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.12.0")
    ],
    targets: [
        .target(
            name: "MyIDECore",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/MyIDECore"
        ),
        .executableTarget(
            name: "MyIDESampleMacApp",
            dependencies: [
                "MyIDECore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/MyIDESampleMacApp"
        ),
        .executableTarget(
            name: "MyIDECLI",
            dependencies: ["MyIDECore"],
            path: "Sources/MyIDECLI"
        )
    ]
)
