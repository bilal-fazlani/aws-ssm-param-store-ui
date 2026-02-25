// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AWSSSMParamStoreUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AWSSSMParamStoreUILogic",
            targets: ["AWSSSMParamStoreUILogic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AWSSSMParamStoreUILogic",
            dependencies: [
                .product(name: "AWSClientRuntime", package: "aws-sdk-swift"),
                .product(name: "AWSSSM", package: "aws-sdk-swift"),
            ]
        ),
        .testTarget(
            name: "AWSSSMParamStoreUILogicTests",
            dependencies: ["AWSSSMParamStoreUILogic"]),
    ]
)

