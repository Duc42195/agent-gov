# Mẫu báo cáo plan-check (Tiếng Việt)

File này quyết định báo cáo trông thế nào: bố cục trả về, các cột của bảng, từng từ và emoji.
Sửa thoải mái. `plan_check.py` chỉ điền dữ liệu vào đây.

- Muốn ghi đè theo dự án: đặt `.agents/templates/plan-check.vi.md`, file đó thắng file này.
- Tạo ngôn ngữ khác: chép file này thành `plan-check.<lang>.md`, chạy với `--lang <lang>`.
- Chỉ ba khối code bên dưới được đọc. Phần còn lại chỉ là tài liệu.

## 1. Mẫu trả về

Placeholder: `{date}` `{verdict}` `{summary}` `{sources}` `{table}` `{confirm}` (rỗng nếu không có gì cần xác nhận).

````report
## {date} — {verdict}
{summary}
{sources}

{table}

{confirm}
````

## 2. Mẫu bảng

Đúng hai dòng: dòng tiêu đề, rồi dòng mẫu cho mỗi task. Dòng kẻ ngăn được thêm tự động.
Placeholder của dòng: `{id}` `{title}` `{owner}` `{status}` `{est}` `{start}` `{end}` `{plan}` `{git}` `{progress}` `{blocks}`.
Thêm, bớt, đổi thứ tự cột bằng cách sửa cả hai dòng.

````table
| ID | Task | Owner | Est | Kế hoạch | Git | Tiến độ | Chặn ai |
| {id} | {title} | {owner} | {est} | {plan} | {git} | {progress} | {blocks} |
````

## 3. Nhãn

Mỗi dòng `key = value`. Giữ nguyên mọi key, chỉ đổi value. `{x}` là chỗ công cụ điền số liệu.

````labels
# kết luận: ĐÚNG TIẾN ĐỘ trừ khi có ít nhất một task chưa giao đã quá hạn
ok = 🟢 **ĐÚNG TIẾN ĐỘ**
late = 🔴 **CHẬM TIẾN ĐỘ**

# dòng tóm tắt
n_late = {n} task trễ hạn: {ids}
due = hạn hôm nay: {ids}
mismatch = đánh dấu done nhưng git không có: {ids}
blk_yes = Chặn người khác: **có** ({a} task đang giữ {b} task)
blk_no = Chặn người khác: **không**

# dòng nguồn
src = Nguồn: plan ({n} task, {done} done) · {branch} head `{sha}` {sync} · {mrs}
sync_ok = khớp remote ✅
sync_stale = ⚠️ remote đã là {r}, local cũ
sync_none = (chưa có remote)
sync_skip = (chưa so sánh: --no-fetch)
mrs = quét {n} MR/PR
mrs_unverified = chưa xác minh MR còn mở hay đã đóng
nogit = ⚠️ không có lịch sử git: bỏ cột Git, chỉ dùng status trong plan

# cột Tiến độ
merged_todo = ✅ đã merge, chờ mark done
done = ✅ done
late_s = 🔴 CHẬM +{d}d
waiting = (MR chờ merge)
today = 🟡 hạn hôm nay
no_mr = chưa có MR
future = ⏳ chưa tới (bắt đầu {d})
ontime = 🟢 trong hạn
review = 🔎 done, MR chờ review/merge
mism = ⚠️ đánh dấu done, git không có

# cột Git và Chặn ai
nocode = chưa có code
merge = merge {x}
leftover = (MR !{n} vẫn nhắc tới, chưa xác minh còn mở)
adr_wait = chờ ADR {x}
none = —

# dòng dưới bảng
confirm = **Đã merge nhưng chưa mark done:** {ids}. Chỉ mark done sau khi user xác nhận.
````
