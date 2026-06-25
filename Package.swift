// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubtitleBurner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SubtitleBurner",
            targets: ["SubtitleBurner"]
        )
    ],
    targets: [
        .target(
            name: "SubtitleBurner",
            path: ".",
            exclude: [
                ".DS_Store",
                ".build",
                ".clang-module-cache",
                ".git",
                ".gitignore",
                ".pycache",
                "MediaDownloaderIcon-1024.png",
                "MediaDownloaderIcon.iconset",
                "SubtitleBurner.app",
                "SubtitleBurnerIcon-1024.png",
                "SubtitleBurnerIcon.iconset",
                "MediaDownloader.app",
                "scripts",
                "README.md",
                "build.sh",
                "build_all_dmg.sh",
                "build_media_downloader.sh",
                "fix_subtitle_size.sh",
                "MediaDownloaderApp.swift",
                "swiftpm-build",
                "SubtitleBurnerApp.swift",
                "SubtitleBurnerTests.swift"
            ],
            sources: [
                "SRTParser.swift",
                "ASSWriter.swift",
                "Settings.swift",
                "KeychainStore.swift",
                "TranslationService.swift",
                "SubtitlePreviewCore.swift",
                "SubtitlePreviewWindow.swift",
                "PipelineRunner.swift"
            ]
        ),
        .testTarget(
            name: "SubtitleBurnerTests",
            dependencies: ["SubtitleBurner"],
            path: ".",
            exclude: [
                ".DS_Store",
                ".build",
                ".clang-module-cache",
                ".git",
                ".gitignore",
                ".pycache",
                "ASSWriter.swift",
                "KeychainStore.swift",
                "MediaDownloader.app",
                "MediaDownloaderApp.swift",
                "MediaDownloaderIcon-1024.png",
                "MediaDownloaderIcon.iconset",
                "Package.swift",
                "PipelineRunner.swift",
                "README.md",
                "SRTParser.swift",
                "Settings.swift",
                "SubtitleBurner.app",
                "SubtitleBurnerApp.swift",
                "SubtitleBurnerIcon-1024.png",
                "SubtitleBurnerIcon.iconset",
                "SubtitlePreviewWindow.swift",
                "SubtitlePreviewCore.swift",
                "TranslationService.swift",
                "build.sh",
                "build_all_dmg.sh",
                "build_media_downloader.sh",
                "fix_subtitle_size.sh",
                "scripts",
                "swiftpm-build"
            ],
            sources: [
                "SubtitleBurnerTests.swift"
            ]
        )
    ]
)
