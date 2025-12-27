## 2024-05-23 - [Form & Navigation Accessibility]
**Learning:** Consistent application of `labelText` across all forms ensures context retention for users during data entry. Tooltips on navigation buttons (Back, Settings, Add) are critical for screen reader users and desktop hover states.
**Action:** Enforce a check for `labelText` on all `TextFormField`s and `tooltip` on all `IconButton`s during code reviews.
