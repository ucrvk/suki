import 'package:flutter_test/flutter_test.dart';
import 'package:suki/utils/app_tabs.dart';

void main() {
  group('bodyOrder', () {
    test('contains the queue tab only when it is enabled', () {
      expect(AppTabs.bodyOrder(queueEnabled: false), [
        AppTabs.booking,
        AppTabs.schedule,
        AppTabs.intro,
        AppTabs.me,
      ]);
      expect(AppTabs.bodyOrder(queueEnabled: true), [
        AppTabs.queue,
        AppTabs.booking,
        AppTabs.schedule,
        AppTabs.intro,
        AppTabs.me,
      ]);
    });
  });

  group('destinationOrder', () {
    test('narrow folds the feedback group into a single intro item', () {
      expect(AppTabs.destinationOrder(queueEnabled: false, wide: false), [
        AppTabs.booking,
        AppTabs.schedule,
        AppTabs.intro,
        AppTabs.me,
      ]);
      expect(AppTabs.destinationOrder(queueEnabled: true, wide: false), [
        AppTabs.queue,
        AppTabs.booking,
        AppTabs.schedule,
        AppTabs.intro,
        AppTabs.me,
      ]);
    });

    test('wide expands the feedback group into four items', () {
      expect(AppTabs.destinationOrder(queueEnabled: false, wide: true), [
        AppTabs.booking,
        AppTabs.schedule,
        ...AppTabs.feedbackGroup,
        AppTabs.me,
      ]);
      expect(AppTabs.destinationOrder(queueEnabled: true, wide: true), [
        AppTabs.queue,
        AppTabs.booking,
        AppTabs.schedule,
        ...AppTabs.feedbackGroup,
        AppTabs.me,
      ]);
    });
  });

  group('bodyIndex', () {
    test('maps every feedback tab to the shared FeedbackPage slot', () {
      for (final tabId in AppTabs.feedbackGroup) {
        expect(AppTabs.bodyIndex(tabId: tabId, queueEnabled: false), 2);
        expect(AppTabs.bodyIndex(tabId: tabId, queueEnabled: true), 3);
      }
    });

    test('maps the other tabs to their own slots', () {
      expect(AppTabs.bodyIndex(tabId: AppTabs.queue, queueEnabled: true), 0);
      expect(AppTabs.bodyIndex(tabId: AppTabs.booking, queueEnabled: true), 1);
      expect(AppTabs.bodyIndex(tabId: AppTabs.booking, queueEnabled: false), 0);
      expect(
        AppTabs.bodyIndex(tabId: AppTabs.schedule, queueEnabled: false),
        1,
      );
      expect(AppTabs.bodyIndex(tabId: AppTabs.schedule, queueEnabled: true), 2);
      expect(AppTabs.bodyIndex(tabId: AppTabs.me, queueEnabled: false), 3);
      expect(AppTabs.bodyIndex(tabId: AppTabs.me, queueEnabled: true), 4);
    });
  });

  group('destinationIndex', () {
    test('narrow always highlights the folded feedback item', () {
      for (final tabId in AppTabs.feedbackGroup) {
        expect(
          AppTabs.destinationIndex(
            tabId: tabId,
            feedbackSegment: 2,
            queueEnabled: false,
            wide: false,
          ),
          2,
        );
      }
      expect(
        AppTabs.destinationIndex(
          tabId: AppTabs.guestbook,
          feedbackSegment: 2,
          queueEnabled: true,
          wide: false,
        ),
        3,
      );
    });

    test('wide highlights the matching feedback sub-item', () {
      expect(
        AppTabs.destinationIndex(
          tabId: AppTabs.intro,
          feedbackSegment: 0,
          queueEnabled: false,
          wide: true,
        ),
        2,
      );
      expect(
        AppTabs.destinationIndex(
          tabId: AppTabs.reviews,
          feedbackSegment: 1,
          queueEnabled: false,
          wide: true,
        ),
        3,
      );
      expect(
        AppTabs.destinationIndex(
          tabId: AppTabs.guestbook,
          feedbackSegment: 2,
          queueEnabled: false,
          wide: true,
        ),
        4,
      );
      expect(
        AppTabs.destinationIndex(
          tabId: AppTabs.photoWall,
          feedbackSegment: 3,
          queueEnabled: false,
          wide: true,
        ),
        5,
      );
    });

    test('respects the queue offset', () {
      expect(
        AppTabs.destinationIndex(
          tabId: AppTabs.me,
          feedbackSegment: 0,
          queueEnabled: true,
          wide: true,
        ),
        7,
      );
      expect(
        AppTabs.destinationIndex(
          tabId: AppTabs.queue,
          feedbackSegment: 0,
          queueEnabled: true,
          wide: true,
        ),
        0,
      );
    });
  });
}
