//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-hitch open source project
//
// Copyright (c) 2026 the swift-hitch project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Hitch
import SwiftUI

struct ItemList: View {
  @State private var path: [Int] = []

  var body: some View {
    NavigationStack(path: $path) {
      List(0..<Catalog.itemCount, id: \.self) { index in
        Button {
          // At the top of the handler: measures from the finger lifting to here, to the next
          // frame, and the longest frame while the detail screen comes in.
          Hitch.markInteraction("open.detail")
          path.append(index)
        } label: {
          HStack(spacing: 12) {
            Picture(name: "thumbnail.load", index: index, side: 88)
              .frame(width: 44, height: 44)
              .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Item \(index + 1)")
              .foregroundStyle(.primary)
          }
        }
      }
      .navigationTitle(Catalog.drawsOnMainThread ? "Main thread" : "Background")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Text(Hitch.isRecording ? "Recording" : "Not recording")
            .font(.footnote)
            .foregroundStyle(Hitch.isRecording ? .red : .secondary)
        }
      }
      .navigationDestination(for: Int.self) { index in
        Picture(name: "detail.load", index: index, side: 600)
          .aspectRatio(1, contentMode: .fit)
          .padding()
          .navigationTitle("Item \(index + 1)")
      }
    }
  }
}

/// Shows the picture of an item once it has been loaded.
struct Picture: View {
  let name: StaticString
  let index: Int
  let side: CGFloat

  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Color.secondary.opacity(0.15)
      if let image {
        Image(uiImage: image).resizable()
      }
    }
    .task(id: index) {
      image = await PictureStore.shared.picture(name, for: index, side: side)
    }
  }
}
