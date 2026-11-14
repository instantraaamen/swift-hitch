# swift-hitch

実機を人が操作しているあいだのヒッチ(コマの遅れ)を測り、変更の前後で比べます。

[English](README.md)

スクロールの性能は UI テストで測るのが一般的です。しかしテストからアプリを操作すると、アクセシビリティが有効になり、操作のたびにビューの階層が読まれます。その処理は、測りたいアプリのメインスレッドに乗ります。同じスクロールでも、テストが操作したときは手で操作したときより何倍も悪い数字になることがあります。

`swift-hitch` は、テストランナーを使わずに測ります。

- **`Hitch`**(ライブラリ): アプリ自身がコマの間隔と、名前を付けた区間の長さを記録し、Documents に書き出します。
- **`hitch`**(コマンド): 記録を有効にしてアプリを実機で起動し、操作が終わったら記録を回収して、複数回の結果を比べます。

Instruments の代わりではなく、補うものです。ビルドどうしで比べられる数字がほしいとき、実データの入った実機でしか出ない問題を追うとき、Instruments が端末につながらないときに使えます。

得られるのは、何が変わったか、その差がぶれより大きいかを示す表です。次の表は、[サンプルアプリ](Examples/HitchExample)を iPhone 18 Pro で手でスクロールして測ったものです(0.1.0 での記録)。変更前は絵をメインスレッドで描き、変更後はバックグラウンドで描いています。

```
median of 3 run(s) before, 3 run(s) after
metric                              before  after  change  noise    verdict
frame.max                              167   82.0   -84.6   18.2   improved
hitchTimeRatio                         130   30.0   -99.9   64.5   improved
open.detail.longestFrameAfter.p95      167   52.2    -114   18.2   improved
open.detail.touchUpToHandler.p95      31.3   28.7    -2.6    3.1  unchanged
thumbnail.load[miss].p95               5.2    435    +430    1.7  regressed
```

最後の行は間違いではありません。何枚も同時に描くようになると 1 枚あたりの時間は延びますが、スクロールは滑らかになります。数字の読み方と、自分のアプリに入れる前に試す手順は、サンプルの README にあります。

## 使い方

起動時に記録を始めます。`--hitch-record` 付きで起動したときだけ動きます。

```swift
import Hitch

#if DEBUG
  Hitch.startIfRequested(metadata: ["itemCount": "\(store.count)"])
#endif
```

すでに `OSSignposter` を使っているなら、`HitchSignposter` に替えてください。同じ signpost を出しつつ、記録中は区間の長さも同じ名前で保存します。

```swift
let signposter = HitchSignposter(subsystem: "com.example.app", category: "Images")

let state = signposter.beginInterval("image.load")
let image = try await loader.image(for: item)
signposter.endInterval("image.load", state, tag: image.wasCached ? "hit" : "miss")
```

- `tag` は、同じ名前でも比べられないもの(キャッシュに当たった・外れた など)を分けます。
- 始めたまま閉じなかった区間は数えて報告します。
- タップの処理の頭で `Hitch.markInteraction("open.detail")` を呼ぶと、指が離れてから処理まで・次のコマまで・その後 250 ミリ秒の最長のコマを記録します。

Mac からは次のように集めて比べます。

```sh
swift run hitch record --device <UDID> --bundle-id com.example.app --label before
swift run hitch compare --before hitch-recordings/before-*.json --after hitch-recordings/after-*.json --goals goals.json
```

- 1 回の計測はぶれるので、変更の前後をそれぞれ数回ずつ記録し、中央値で比べます。変更前のぶれ幅より大きい差だけを「変わった」と判定します。
- 値が二つの山に分かれているときは知らせます(中央値や p95 は片方の山しか表しません)。
- 比べる前に、条件がそろっているかを確かめます(端末・OS・ビルド構成・リフレッシュレート・低電力モード・端末の熱・記録の長さ・メタ情報)。
- 目標値のファイルに書いた名前に当たる記録が無いときは、合格にせず「確かめられなかった」と知らせます。

## 数字の意味

用語は Apple のものです。hitch time ratio は 1 秒あたりの遅れ(ms/s)で、5 未満なら良好、5〜10 は気づかれる、10 を超えると邪魔になります。

メインスレッドの `CADisplayLink` で見ているので、ここでのヒッチは「画面がコマを求めたときにメインスレッドが忙しかった」ことを表します。Instruments や MetricKit は画面側で測るので、同じ操作でも値が違うことがあります。ビルドどうしを比べるための数字として使ってください。

120 Hz の iPhone では、画面は速さを変えながら動きます。実測では、止まった画面は 60 Hz、スクロール中は 60・80・120 Hz を行き来しました。記録用の `CADisplayLink` は速さを要求せずに画面に付いていき、コマごとに、そのとき画面が期待していた間隔と比べてヒッチを判定します。60 Hz を超える速さは、Info.plist に `CADisableMinimumFrameDurationOnPhone` を入れたアプリでしか使えません。

ただし、このキーを入れただけでは `CADisplayLink` は 120 Hz になりません。同じ記録の中で、範囲を指定しないままの `CADisplayLink` は、止まった画面で 60 Hz、スクロール中で 60〜80 Hz でした。その横で、記録用のリンクにはコマの 4 分の 1 から 3 分の 1 が 120 Hz で届いています。自分のコードで `CADisplayLink` からアニメーションを動かしたり時間を測ったりしているなら、`preferredFrameRateRange` で上限を画面の最大値まで広げてください。そうしないと速いコマは届きません。これは iPhone 18 Pro(iOS 27.2)1 台で、各 1 回測った結果です。

詳しくは [README.md](README.md) を見てください。

## ライセンス

Apache License 2.0
