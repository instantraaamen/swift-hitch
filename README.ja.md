# swift-hitch

実機で人が操作しているあいだのヒッチ(カクつき)を測り、変更の前後を比べるためのパッケージです。

[English](README.md)

スクロールの性能は XCUITest と `XCTOSSignpostMetric` で測るのが普通ですが、テストから操作するとアクセシビリティが有効になり、操作のたびに画面の構造が読まれます。その負荷が測りたいアプリのメインスレッドに乗ります。同じスクロールでも、テストから操作すると手で操作したときの何倍も悪い数字になることがあります。

`swift-hitch` はテストランナーを使いません。

- **`Hitch`**(ライブラリ): アプリ自身がコマの間隔と、名前を付けた区間の長さを記録し、Documents に書きます。
- **`hitch`**(CLI): 記録を有効にして実機でアプリを起動し、操作が終わるのを待ち、記録を回収して比べます。

## 記録する

```swift
import Hitch

@main
struct MyApp: App {
  init() {
    #if DEBUG
      Hitch.startIfRequested()
    #endif
  }
}
```

`--hitch-record` を付けて起動したときだけ記録します。区間は `Hitch.sample("image.load", since: start)` や `Hitch.measure("list.layout") { ... }` で足せます。タップの反応は、処理の頭で `Hitch.markInteraction("open.detail")` を呼びます。

## 回収して比べる

```sh
swift run hitch record --device <UDID> --bundle-id com.example.app --label before
swift run hitch compare --before hitch-recordings/before-*.json --after hitch-recordings/after-*.json --goals goals.json
```

1 回の記録はぶれるので、同じ操作で数回ずつ記録し、中央値で比べます。変化として数えるのは、変更前のぶれ幅より大きく、かつ変更前の値の 1% より大きいものだけです。

## 数字の意味

用語は Apple のものです。ヒッチ時間の比率(hitch time ratio)は 1 秒あたりの遅れで、5 ms/s 未満が良好、5〜10 が気づく、10 超が邪魔になる水準です。メインの RunLoop の `CADisplayLink` で見ているので、メインスレッドが詰まった遅れを測ります。レンダーサーバだけで遅れたコマは見えません。

詳しくは [README.md](README.md) を見てください。

## ライセンス

MIT
