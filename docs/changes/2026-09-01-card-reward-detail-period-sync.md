# 信用卡紅利回饋明細頁未沿用帳戶頁瀏覽週期

## 問題

在帳戶明細頁(`account_detail_page.dart`)透過帳單彙總卡片的 `</>` 切到上一期/下一期後,點擊「紅利回饋」清單中的規則項目進入 `CardRewardDetailPage`,該頁一律以當期(`_offset = 0`)開啟,而非使用者剛才在帳戶頁瀏覽的週期。使用者必須在明細頁再手動點一次「上一期」才能看到正確資料。

## 原因

`CardRewardDetailPage` 的建構子沒有接收週期參數,`_offset` 直接寫死為 `0`;帳戶頁的 `onTap` 導覽也沒有把當下的 `_billingPeriodOffset` 傳過去,即使它在該閉包中已經在作用域內。

## 修改

- [card_reward_detail_page.dart](../../lib/pages/account/card_reward_detail_page.dart):新增 `initialOffset`(預設 `0`,保留其他呼叫路徑/未來用法的相容性)建構子參數,`_offset` 改為 `late int _offset = widget.initialOffset;`。
- [account_detail_page.dart](../../lib/pages/account/account_detail_page.dart):導覽至 `CardRewardDetailPage` 時多帶入 `initialOffset: _billingPeriodOffset`。

明細頁進入後仍可獨立地用自己的 `</>` 繼續前後翻頁,只是初始值改為沿用帳戶頁當下瀏覽的週期,不影響原本「兩邊週期導覽互相獨立」的設計。
