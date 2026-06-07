## activity/ — Activity Feed

- **models/activity_log_model.dart**: Activity entry across events
- **services/activity_service.dart**: Cursor-paginated activity-log fetch (fetchActivityPageRaw, 50/page). Event expense audit entries are written server-side by the `expenseAuditLogger` Cloud Functions trigger (#248), not the client.
- **screens/activity_feed_screen.dart**: Timeline of participant actions
- **keys/activity_keys.dart**: Widget keys for the activity feed
- **utils/activity_display.dart**: Display formatting helpers for activity rows
