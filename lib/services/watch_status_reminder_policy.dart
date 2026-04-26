import 'package:drama_tracker/models/anime_progress.dart';

class WatchStatusReminderPolicy {
  const WatchStatusReminderPolicy._();

  static bool canEnableReminderForSelectedStatusName(String? statusName) {
    return statusName == 'watching';
  }

  static bool allowsReminderForProgress(AnimeProgress progress) {
    return progress.statusSelected && progress.status.name == 'watching';
  }

  static AnimeProgress normalize(AnimeProgress progress) {
    if (!allowsReminderForProgress(progress) && progress.reminderEnabled) {
      return progress.copyWith(reminderEnabled: false);
    }
    return progress;
  }
}
