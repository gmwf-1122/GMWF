import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/utils/formatters.dart';

TextEditingValue _v(String t) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

void main() {
  const f = DoseTimingInputFormatter();
  String type(String typed) {
    var cur = _v('');
    for (final ch in typed.split('')) {
      cur = f.formatEditUpdate(cur, _v(cur.text + ch));
    }
    return cur.text;
  }

  test('digits get + automatically', () {
    expect(type('1'), '1');
    expect(type('10'), '1+0');
    expect(type('101'), '1+0+1');
    expect(type('111'), '1+1+1');
    expect(type('9999'), '9+9+9'); // max 3 doses: Morning+Evening+Night
  });
  test('typed + is ignored (no doubles)', () {
    expect(type('1+0+1'), '1+0+1');
  });
  test('backspace over + removes the dose before it', () {
    expect(f.formatEditUpdate(_v('1+0+1'), _v('1+0+')).text, '1+0');
    expect(f.formatEditUpdate(_v('1+0'), _v('1+')).text, '1');
  });
}
