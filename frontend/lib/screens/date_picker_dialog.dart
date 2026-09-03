import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_widgets.dart';

/// 日期选择对话框：同时提供日期选择框与手动键盘输入框，二者同步。
/// 使用显式维护月份的日历，避免 CalendarDatePicker 在窄窗口重布局时翻月错乱。
class DatePickerDialogWidget extends StatefulWidget {
  final String? initial;
  final String title;
  const DatePickerDialogWidget({super.key, this.initial, this.title = '选择日期'});

  @override
  State<DatePickerDialogWidget> createState() => _S();
}

class _S extends State<DatePickerDialogWidget> {
  static final DateTime _firstDate = DateTime(2000, 1, 1);
  static final DateTime _lastDate = DateTime(2100, 12, 31);
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  late final TextEditingController _ctrl;
  DateTime? _picked;
  late DateTime _displayedMonth;
  bool _yearDateMode = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial ?? '';
    _picked = _parseDate(s);
    final base = _picked ?? DateTime.now();
    _displayedMonth = DateTime(base.year, base.month);
    _ctrl = TextEditingController(text: s);
  }

  DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    try {
      return DateFormat('yyyy/MM/dd').parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(DateTime date) {
    setState(() {
      _picked = date;
      _displayedMonth = DateTime(date.year, date.month);
      _ctrl.text = DateFormat('yyyy/MM/dd').format(date);
    });
  }

  void _changeMonth(int delta) {
    final candidate = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + delta,
    );
    final firstMonth = DateTime(_firstDate.year, _firstDate.month);
    final lastMonth = DateTime(_lastDate.year, _lastDate.month);
    if (candidate.isBefore(firstMonth) || candidate.isAfter(lastMonth)) return;
    setState(() => _displayedMonth = candidate);
  }

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildCalendar(BuildContext context) {
    final theme = Theme.of(context);
    final firstWeekday = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
      1,
    ).weekday;
    final days = DateUtils.getDaysInMonth(
      _displayedMonth.year,
      _displayedMonth.month,
    );
    final cells = <Widget>[];

    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= days; day++) {
      final date = DateTime(_displayedMonth.year, _displayedMonth.month, day);
      final selected = _sameDay(_picked, date);
      final today = _sameDay(DateTime.now(), date);
      cells.add(
        Padding(
          padding: const EdgeInsets.all(2),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _set(date),
            child: Container(
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    )
                  : today
                      ? BoxDecoration(
                          border: Border.all(color: theme.colorScheme.primary),
                          shape: BoxShape.circle,
                        )
                      : null,
              child: Text(
                '$day',
                style: selected
                    ? TextStyle(color: theme.colorScheme.onPrimary)
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('month-date-picker'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    key: const ValueKey('year-selector'),
                    onPressed: () => setState(() => _yearDateMode = true),
                    child: Text(
                      '${_displayedMonth.year}年',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    DateFormat('MM月').format(_displayedMonth),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.15,
          children: [
            for (final weekday in _weekdays)
              Center(
                child: Text(
                  weekday,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ...cells,
          ],
        ),
      ],
    );
  }

  void _selectYear(DateTime date) {
    setState(() {
      // 年份窗口只负责切换按月日历当前显示的年份，不直接修改最终日期。
      _displayedMonth = DateTime(date.year, _displayedMonth.month);
      _yearDateMode = false;
    });
  }

  Widget _buildYearDatePicker() {
    return SizedBox(
      key: const ValueKey('year-date-picker'),
      height: 360,
      child: Column(
        children: [
          Text(
            '选择年份后返回按月日历，再选择最终日期',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: YearPicker(
              firstDate: _firstDate,
              lastDate: _lastDate,
              selectedDate: _displayedMonth,
              currentDate: DateTime.now(),
              onChanged: _selectYear,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 48;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(widget.title),
      content: SizedBox(
        width: availableWidth.clamp(280.0, 360.0).toDouble(),
        child: _yearDateMode
            ? _buildYearDatePicker()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _ctrl,
                      decoration: appInputDecoration(
                        context,
                        labelText: 'YYYY/MM/DD',
                        hintText: '2026/09/01',
                        suffixIcon: const Icon(Icons.calendar_month),
                      ),
                      onChanged: (value) {
                        final date = _parseDate(value);
                        if (date == null ||
                            date.isBefore(_firstDate) ||
                            date.isAfter(_lastDate)) {
                          return;
                        }
                        setState(() {
                          _picked = date;
                          _displayedMonth = DateTime(date.year, date.month);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildCalendar(context),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        if (_yearDateMode)
          TextButton.icon(
            key: const ValueKey('return-to-month-picker'),
            onPressed: () => setState(() => _yearDateMode = false),
            icon: const Icon(Icons.calendar_month),
            label: const Text('返回按月选择'),
          )
        else
          FilledButton(
            onPressed: () {
              final date = _parseDate(_ctrl.text);
              Navigator.pop(
                context,
                date == null ? null : DateFormat('yyyy/MM/dd').format(date),
              );
            },
            child: const Text('确定'),
          ),
      ],
    );
  }
}

/// 起止日期选择行：两个输入框 + 两个日历按钮
/// 通过 onChanged 回调通知外部当前 from/to 值
class DateRangeField extends StatefulWidget {
  final String? initialFrom;
  final String? initialTo;
  final String label;
  final void Function(String? from, String? to)? onChanged;
  const DateRangeField({
    super.key,
    this.initialFrom,
    this.initialTo,
    this.label = '日期范围',
    this.onChanged,
  });

  @override
  State<DateRangeField> createState() => _DateRangeFieldState();
}

class _DateRangeFieldState extends State<DateRangeField> {
  late TextEditingController _from;
  late TextEditingController _to;

  @override
  void initState() {
    super.initState();
    _from = TextEditingController(text: widget.initialFrom ?? '');
    _to = TextEditingController(text: widget.initialTo ?? '');
    _from.addListener(_notify);
    _to.addListener(_notify);
  }

  void _notify() {
    if (widget.onChanged != null) {
      widget.onChanged!(
        _from.text.isEmpty ? null : _from.text,
        _to.text.isEmpty ? null : _to.text,
      );
    }
  }

  @override
  void dispose() {
    _from.removeListener(_notify);
    _to.removeListener(_notify);
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final v = await showDialog<String>(
      context: context,
      builder: (_) => DatePickerDialogWidget(
        initial: from ? _from.text : _to.text,
        title: from ? '开始日期' : '结束日期',
      ),
    );
    if (v == null) return;
    setState(() {
      if (from) {
        _from.text = v;
      } else {
        _to.text = v;
      }
    });
  }

  Widget _dateInput(TextEditingController controller, bool from) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        decoration: appInputDecoration(
          context,
          hintText: from ? '开始' : '结束',
          suffixIcon: IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () => _pick(from),
          ),
          compact: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inputs = <Widget>[
          _dateInput(_from, true),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('~'),
          ),
          _dateInput(_to, false),
        ];
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 6,
                children: inputs,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: Text(widget.label)),
            ...inputs,
          ],
        );
      },
    );
  }
}
