/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Lottie
import LottieUI
import Defaults
import AVKit

struct IdleAnimationView: View {
    var animation: CustomIdleAnimation? = nil
    var preferredSize: CGSize? = nil
    var loops: Bool = true
    var onComplete: (() -> Void)? = nil
    @Default(.selectedIdleAnimation) var selectedAnimation
    @Default(.animationTransformOverrides) var overrides

    private var resolvedAnimation: CustomIdleAnimation? {
        animation ?? selectedAnimation
    }

    var body: some View {
        Group {
            if let animation = resolvedAnimation {
                AnimationContentView(
                    animation: animation,
                    loops: loops,
                    preferredSize: preferredSize,
                    onComplete: onComplete
                )
                    .id("\(animation.id)-\(overrides[animation.id.uuidString]?.hashValue ?? 0)-\(loops)-\(preferredSize?.width ?? 0)-\(preferredSize?.height ?? 0)")
            } else {
                EmptyView()
            }
        }
    }
}

struct EasterEggAnimationView: View {
    @ObservedObject private var manager = EasterEggAnimationManager.shared

    var body: some View {
        Group {
            if manager.isActive {
                switch manager.playbackMode {
                case .neonEyes:
                    NeonEyesAnimationView(playbackMode: .oneShot, placement: .center) {
                        manager.stopPlayback(resetPlayedFlag: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .none:
                    EmptyView()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AnimationContentView: View {
    let animation: CustomIdleAnimation
    let loops: Bool
    var preferredSize: CGSize? = nil
    var onComplete: (() -> Void)? = nil

    var body: some View {
        let config = animation.getTransformConfig()
        let contentWidth = preferredSize?.width ?? config.cropWidth * config.scale
        let contentHeight = preferredSize?.height ?? config.cropHeight * config.scale

        switch animation.source {
        case .shimmer:
            NotchShimmerView(cornerRadius: min(contentWidth, contentHeight) / 2)
                .frame(width: contentWidth, height: contentHeight)
                .offset(x: config.offsetX, y: config.offsetY)
                .rotationEffect(.degrees(config.rotation))
                .opacity(config.opacity)
                .padding(.bottom, config.paddingBottom)
                .clipped()

        case .neonEyes:
            NeonEyesAnimationView(
                playbackMode: loops ? .loop : .oneShot,
                placement: preferredSize == nil ? .center : .side,
                onComplete: onComplete
            )
                .frame(width: contentWidth, height: contentHeight)
                .offset(x: config.offsetX, y: config.offsetY)
                .rotationEffect(.degrees(config.rotation))
                .opacity(config.opacity)
                .padding(.bottom, config.paddingBottom)
                .clipped()

        case .lottieFile(let url):
            LottieView(state: LUStateData(
                type: .loadedFrom(url),
                speed: animation.speed,
                loopMode: loops ? config.loopMode.lottieLoopMode : .playOnce
            ))
            .id(animation.id)
            .aspectRatio(contentMode: preferredSize == nil ? .fit : .fill)
            .frame(width: contentWidth, height: contentHeight)
            .offset(x: config.offsetX, y: config.offsetY)
            .rotationEffect(.degrees(config.rotation))
            .opacity(config.opacity)
            .padding(.bottom, config.paddingBottom)
            .clipped()

        case .lottieURL(let url):
            LottieView(state: LUStateData(
                type: .loadedFrom(url),
                speed: animation.speed,
                loopMode: loops ? config.loopMode.lottieLoopMode : .playOnce
            ))
            .id(animation.id)
            .aspectRatio(contentMode: preferredSize == nil ? .fit : .fill)
            .frame(width: contentWidth, height: contentHeight)
            .offset(x: config.offsetX, y: config.offsetY)
            .rotationEffect(.degrees(config.rotation))
            .opacity(config.opacity)
            .padding(.bottom, config.paddingBottom)
            .clipped()

        case .videoFile(let url):
            LoopingVideoView(url: url, loops: loops, onComplete: onComplete)
                .aspectRatio(contentMode: preferredSize == nil ? .fit : .fill)
                .frame(width: contentWidth, height: contentHeight)
                .offset(x: config.offsetX, y: config.offsetY)
                .rotationEffect(.degrees(config.rotation))
                .opacity(config.opacity)
                .padding(.bottom, config.paddingBottom)
                .clipped()
        }
    }
}

private struct LoopingVideoView: View {
    let url: URL
    let loops: Bool
    var onComplete: (() -> Void)? = nil
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        VideoPlayer(player: player)
            .disabled(true)
            .onAppear {
                let item = AVPlayerItem(url: url)
                let newPlayer = AVPlayer(playerItem: item)
                player = newPlayer
                if loops {
                    endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { _ in
                        newPlayer.seek(to: .zero)
                        newPlayer.play()
                    }
                } else {
                    endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { _ in
                        onComplete?()
                    }
                }
                newPlayer.play()
            }
            .onDisappear {
                if let endObserver {
                    NotificationCenter.default.removeObserver(endObserver)
                }
                player?.pause()
                player = nil
                endObserver = nil
            }
    }
}
