# THE IDOLM@STER 标识素材

本目录保存应援色目录使用的企划标识源图和来源记录。素材只用于非官方的本地灯控界面；收录不表示与 Bandai Namco Entertainment 存在隶属、授权或背书关系。

manifest.json 是每个素材的来源 URL、抓取日期、源文件 SHA-256、生成 PNG SHA-256 以及许可/商标备注的唯一记录。需要重新生成 Android 使用的 320×160 透明图时，在 android/ 目录运行对应的素材脚本：

~~~
python tools/palette/fetch_imas_logos.py
python tools/palette/crawl_imas.py
python tools/palette/build_catalog.py
~~~

处理流程只按比例缩放并居中留透明边，不改色、不拉伸、不裁切。来源页中的公共领域文字标识说明不等于商标使用许可，分发前仍需自行确认权利范围。
