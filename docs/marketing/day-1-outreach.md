# Rihla Day-1 Outreach Sheet

Date: 2026-06-27

Objective: send the first 10 personal asks and create the first measurable
install/activation loop.

Use this with:

- `first-100-cohort-tracker.csv`
- `first-100-command-center.md`
- `first-100-outreach-kit.md`
- `closed-test-access-kit.md`

## Before Sending

For each slot:

1. Replace the blank `champion` cell with a real person.
2. Ask for the Google account they use in the Play Store.
3. Add them to the Play closed-testing access list if the app is still closed.
4. Update the private tester roster, then export the Play upload file with
   `dart tool/export_play_tester_emails.dart ~/Desktop/rihla-first-100-play-testers.csv --output=/tmp/rihla-play-testers.csv`.
5. Upload the generated file to the Play Console tester list.
6. Send the Play opt-in link before the public landing link.
7. Send `https://rihla-safar.web.app/alpha` or
   `https://rihla-safar.web.app/ar/alpha` if they need the access steps.
8. Generate the slot-specific messages:
   `dart tool/first_100_messages.dart --count=10 --language=en`
   or `dart tool/first_100_messages.dart --count=10 --language=ar`.
9. Paste the generated slot-specific message into the DM.
10. Set `first_contact_date` to the send date.
11. Set `follow_up_date` to the next day.

Do not send the message until the person can actually access the Play listing.

## Day-1 Slots

| Slot | Segment | Use case | Channel | Link |
|---:|---|---|---|---|
| 01 | Travel crews | Salalah/weekend/trip expenses | WhatsApp | `https://rihla-safar.web.app/?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100&utm_content=champion_slot_01` |
| 02 | Travel crews | Salalah/weekend/trip expenses | WhatsApp | `https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_02` |
| 03 | Travel crews | Camping/chalet/road trip | WhatsApp | `https://rihla-safar.web.app/split-bills-oman?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_oman&utm_content=champion_slot_03` |
| 04 | Travel crews | Camping/chalet/road trip | WhatsApp | `https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_04` |
| 05 | Travel crews | Group flight/hotel booking | WhatsApp | `https://rihla-safar.web.app/?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100&utm_content=champion_slot_05` |
| 06 | Travel crews | Group flight/hotel booking | WhatsApp | `https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_06` |
| 07 | Travel crews | Fuel/food/stay split | WhatsApp | `https://rihla-safar.web.app/split-bills-oman?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_oman&utm_content=champion_slot_07` |
| 08 | Travel crews | Fuel/food/stay split | WhatsApp | `https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_08` |
| 09 | Travel crews | Weekend outing expenses | Instagram DM | `https://rihla-safar.web.app/?utm_source=instagram&utm_medium=dm&utm_campaign=first_100&utm_content=champion_slot_09` |
| 10 | Travel crews | Weekend outing expenses | Instagram DM | `https://rihla-safar.web.app/ar?utm_source=instagram&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_10` |

## Message: English Slots

If the champion is not already a tester, send the access message from
`closed-test-access-kit.md` first. Then send:

```text
Can you use Rihla for one real shared bill this week?

Best case: a trip, dinner, groceries, fuel, or a booking where one person pays for the group.

Create a group, send the WhatsApp invite, and add the first expense while it is fresh. I need real usage, not compliments.

Link: SLOT_LINK

If you install from a group invite and the code is not filled automatically, go back to the WhatsApp invite link and tap it again after installing.
```

## Message: Arabic Slots

إذا لم يكن الشخص مضافًا كمختبر، أرسل رسالة الوصول من
`closed-test-access-kit.md` أولًا. ثم أرسل:

```text
ممكن تستخدم Rihla لمصاريف مجموعة حقيقية هذا الأسبوع؟

أفضل تجربة: رحلة، عشاء، مشتريات، بترول، أو حجز يدفعه شخص عن المجموعة.

أنشئ مجموعة، أرسل دعوة واتساب، وأضف أول مصروف وهو لا يزال جديد. أحتاج استخدام حقيقي، وليس مجاملة.

الرابط: SLOT_LINK

إذا ثبت التطبيق من رابط دعوة ولم يظهر رمز المجموعة تلقائيًا، ارجع إلى رابط الدعوة في واتساب وافتحه مرة ثانية بعد التثبيت.
```

## Follow-Up After 24 Hours

Send this only if they installed or replied positively:

```text
Did you manage to create the group and send the invite?

The most useful test is:
1. create group
2. invite 2+ people
3. add one real expense
4. check who owes who

What step blocked you?
```

Arabic:

```text
هل قدرت تنشئ المجموعة وترسل الدعوة؟

أهم تجربة بالنسبة لي:
1. إنشاء مجموعة
2. دعوة شخصين أو أكثر
3. إضافة مصروف حقيقي واحد
4. التأكد من من يدين لمن

أي خطوة عطلتك؟
```

## Tracker Updates

After each send:

- `tester_added`: `yes` only after Play access is confirmed.
- `first_contact_date`: send date.
- `follow_up_date`: next-day follow-up date.
- `group_created`: `yes` only after the champion confirms it.
- `invite_sent`: `yes` only after they share the group invite.
- `installs_reported`, `joined_count`, `expenses_count`, `settlements_count`:
  use reported numbers or verified backend/store evidence.
- `top_blocker`: write the exact blocker, for example `Play access`, `invite code lost after install`, `did not know what expense to add`, or `no Android phone`.

Day 1 is successful if at least 10 personal asks are sent and at least 7 people
can access the Play listing.

## End-Of-Day Summary

After updating the tracker, run:

```bash
dart tool/first_100_summary.dart --today=2026-06-27
```

Use the output to update `first-100-command-center.md`. The report does not
print private champion names or tester emails.
