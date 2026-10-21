import 'package:flutter_test/flutter_test.dart';
import 'package:infinitywash/models/order.dart';
import 'package:infinitywash/services/order_service.dart';
import 'package:infinitywash/services/rider_service.dart';
import 'package:infinitywash/services/service_request_service.dart';

void main() {
  // =========================================================================
  // Phase 1: Rider job claim guard
  // =========================================================================
  group('StartJobGuards (rider double-claim protection)', () {
    const me = 'emp-111';
    const other = 'emp-222';

    test('unclaimed pending job is claimable', () {
      expect(
        StartJobGuards.claimUpdateAllowed(
          jobRiderId: null,
          jobStatus: 'pending',
          myEmployeeId: me,
        ),
        isTrue,
      );
      expect(
        StartJobGuards.shouldBlockStart(
          jobRiderId: null,
          jobStatus: 'pending',
          myEmployeeId: me,
        ),
        isFalse,
      );
    });

    test('job already claimed by ANOTHER rider is blocked', () {
      expect(
        StartJobGuards.shouldBlockStart(
          jobRiderId: other,
          jobStatus: 'pending',
          myEmployeeId: me,
        ),
        isTrue,
      );
      expect(
        StartJobGuards.claimUpdateAllowed(
          jobRiderId: other,
          jobStatus: 'pending',
          myEmployeeId: me,
        ),
        isFalse,
        reason: 'atomic UPDATE guard must not match a foreign claim',
      );
    });

    test('job claimed by the SAME rider can be re-claimed (retry path)', () {
      expect(
        StartJobGuards.claimUpdateAllowed(
          jobRiderId: me,
          jobStatus: 'in_progress',
          myEmployeeId: me,
        ),
        isTrue,
      );
      expect(
        StartJobGuards.shouldBlockStart(
          jobRiderId: me,
          jobStatus: 'in_progress',
          myEmployeeId: me,
        ),
        isFalse,
      );
    });

    test('finished jobs are never claimable', () {
      for (final status in const ['pickup_done', 'delivery_done', 'cancelled']) {
        expect(
          StartJobGuards.claimUpdateAllowed(
            jobRiderId: null,
            jobStatus: status,
            myEmployeeId: me,
          ),
          isFalse,
          reason: 'status $status must block the claim UPDATE',
        );
        expect(
          StartJobGuards.shouldBlockStart(
            jobRiderId: null,
            jobStatus: status,
            myEmployeeId: me,
          ),
          isTrue,
        );
      }
    });

    test('claimWon: empty result means lost race, non-empty means won', () {
      expect(StartJobGuards.claimWon(const []), isFalse);
      expect(StartJobGuards.claimWon([{'id': 'job-1'}]), isTrue);
    });

    test('claim payload stamps rider, in_progress status and UTC times', () {
      final now = DateTime.parse('2026-10-05T01:02:03.000Z');
      final payload = StartJobGuards.claimUpdatePayload(
        riderEmployeeId: me,
        wasUnclaimed: true,
        now: now,
      );

      expect(payload['rider_id'], me);
      expect(payload['status'], 'in_progress');
      expect(payload['started_at'], '2026-10-05T01:02:03.000Z');
      expect(payload['updated_at'], payload['started_at']);
      expect(payload['assigned_at'], payload['started_at'],
          reason: 'first claim also stamps assigned_at');
    });

    test('re-claim payload does not overwrite assigned_at', () {
      final payload = StartJobGuards.claimUpdatePayload(
        riderEmployeeId: me,
        wasUnclaimed: false,
        now: DateTime.parse('2026-10-05T01:02:03.000Z'),
      );

      expect(payload.containsKey('assigned_at'), isFalse);
    });

    test('JobClaimedException carries a rider-friendly message', () {
      expect(JobClaimedException().toString(),
          'This job was already taken by another rider.');
    });

    test('riderVisibilityFilter: builds filter for unassigned plus current rider', () {
      expect(
        StartJobGuards.riderVisibilityFilter(me),
        'rider_id.is.null,rider_id.eq.emp-111',
      );
      expect(
        StartJobGuards.riderVisibilityFilter(null),
        'rider_id.is.null',
      );
      expect(
        StartJobGuards.riderVisibilityFilter(''),
        'rider_id.is.null',
      );
    });

    test('isJobVisibleToRider: unassigned and own jobs are visible, other rider jobs are hidden', () {
      // Unassigned job is visible to everyone
      expect(
        StartJobGuards.isJobVisibleToRider(jobRiderId: null, myEmployeeId: me),
        isTrue,
      );
      expect(
        StartJobGuards.isJobVisibleToRider(jobRiderId: null, myEmployeeId: other),
        isTrue,
      );

      // Job taken by 'me' is visible to 'me'
      expect(
        StartJobGuards.isJobVisibleToRider(jobRiderId: me, myEmployeeId: me),
        isTrue,
      );

      // Job taken by 'other' is NOT visible to 'me'
      expect(
        StartJobGuards.isJobVisibleToRider(jobRiderId: other, myEmployeeId: me),
        isFalse,
      );

      // Job taken by anyone is NOT visible if current rider has no employee ID
      expect(
        StartJobGuards.isJobVisibleToRider(jobRiderId: other, myEmployeeId: null),
        isFalse,
      );
    });
  });

  // =========================================================================
  // Phase 2: completeOrder idempotency + loyalty mapping
  // =========================================================================
  group('CompleteOrderGuards (idempotent completion + loyalty)', () {
    test('missing order row → notFound (completeOrder throws)', () {
      expect(CompleteOrderGuards.decideAction(null), CompleteOrderAction.notFound);
    });

    test('already-completed order → skip (no duplicate award)', () {
      expect(
        CompleteOrderGuards.decideAction('completed'),
        CompleteOrderAction.skip,
      );
    });

    test('any other status → completeAndAward', () {
      for (final status in const [
        'pending_pickup',
        'processing',
        'ready',
        'out_for_delivery',
        'pending_approval',
      ]) {
        expect(
          CompleteOrderGuards.decideAction(status),
          CompleteOrderAction.completeAndAward,
          reason: 'status $status should still complete + award',
        );
      }
    });

    test('loads count maps to points with a minimum of 1', () {
      expect(CompleteOrderGuards.loyaltyPointsFor(null), 1);
      expect(CompleteOrderGuards.loyaltyPointsFor(0), 1);
      expect(CompleteOrderGuards.loyaltyPointsFor(1), 1);
      expect(CompleteOrderGuards.loyaltyPointsFor(7), 7);
    });
  });

  // =========================================================================
  // Phase 3: Review lock validity (24h staff review flow)
  // =========================================================================
  group('ServiceRequestService review lock', () {
    test('valid lock held by someone is recognized', () {
      final row = {
        'under_review_by': 'emp-1',
        'under_review_at': DateTime.now().toUtc().toIso8601String(),
      };
      expect(ServiceRequestService.isReviewLockValid(row), isTrue);
    });

    test('lock with no holder or no timestamp is invalid', () {
      expect(
        ServiceRequestService.isReviewLockValid({
          'under_review_by': null,
          'under_review_at': DateTime.now().toUtc().toIso8601String(),
        }),
        isFalse,
      );
      expect(
        ServiceRequestService.isReviewLockValid({
          'under_review_by': '',
          'under_review_at': DateTime.now().toUtc().toIso8601String(),
        }),
        isFalse,
      );
      expect(
        ServiceRequestService.isReviewLockValid({
          'under_review_by': 'emp-1',
          'under_review_at': null,
        }),
        isFalse,
      );
    });

    test('lock older than reviewLockTimeout (30 min) is stale → invalid', () {
      final now = DateTime.parse('2026-10-05T12:00:00.000Z');
      final fresh = {
        'under_review_by': 'emp-1',
        'under_review_at': '2026-10-05T11:45:00.000Z', // 15 min old
      };
      final stale = {
        'under_review_by': 'emp-1',
        'under_review_at': '2026-10-05T10:00:00.000Z', // 2 h old
      };

      expect(ServiceRequestService.isReviewLockValidAt(fresh, now), isTrue);
      expect(ServiceRequestService.isReviewLockValidAt(stale, now), isFalse);
    });

    test('unparseable timestamp is treated as invalid', () {
      expect(
        ServiceRequestService.isReviewLockValid({
          'under_review_by': 'emp-1',
          'under_review_at': 'not-a-date',
        }),
        isFalse,
      );
    });

    test('UTC timestamps parse regardless of local timezone', () {
      final now = DateTime.parse('2026-10-05T23:50:00.000Z');
      final justBeforeExpiry = {
        'under_review_by': 'emp-1',
        'under_review_at': '2026-10-05T23:25:00.000Z',
      };
      expect(
        ServiceRequestService.isReviewLockValidAt(justBeforeExpiry, now),
        isTrue,
      );
    });
  });

  // =========================================================================
  // Phase 4: Order source channel unification
  // =========================================================================
  group('Order source channel', () {
    test('canonical values round-trip', () {
      expect(LaundryOrder.channelFromString('walk_in'), OrderChannel.walkIn);
      expect(LaundryOrder.channelFromString('mobile_app'), OrderChannel.online,
          reason: 'mobile_app is the canonical DB value for the app channel');
    });

    test('legacy online value maps to the app channel', () {
      expect(LaundryOrder.channelFromString('online'), OrderChannel.online);
    });

    test('null and unknown values fall back to the app channel', () {
      expect(LaundryOrder.channelFromString(null), OrderChannel.online);
      expect(LaundryOrder.channelFromString('kiosk'), OrderChannel.online);
    });
  });
}
