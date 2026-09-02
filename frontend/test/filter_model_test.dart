import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/models.dart';

void main() {
  test('expected remaining days is included in filter bodies', () {
    const filter = FilterReq(expectedRemainingDays: 30);
    expect(filter.isEmpty, isFalse);
    expect(filter.toBody()['expected_remaining_days'], 30);
    expect(filter.toQuery()['expected_remaining_days'], '30');
  });
}
