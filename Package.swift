// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DesktopPet", targets: ["DesktopPet"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "DesktopPet", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/DogYawn.json")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "DesktopPetTests", dependencies: ["DesktopPet"])
    ]
)
