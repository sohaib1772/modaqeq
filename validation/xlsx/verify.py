"""Read back workbooks produced by the Dart exporter with an independent reader."""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'build/xlsxcheck'))
import openpyxl

results = []
for name in ('statement', 'inventory', 'invoice'):
    path = root / 'validation/xlsx' / f'{name}.xlsx'
    book = openpyxl.load_workbook(path)
    sheet = book.active
    values = [cell.value for row in sheet for cell in row if cell.value is not None]
    assert sheet.sheet_view.rightToLeft is True
    assert not any(cell.data_type == 'f' for row in sheet for cell in row)
    if name == 'statement':
        for r in range(1, 121):
            for c in range(12):
                assert f'R{r}C{c}' in values
        assert sheet.max_column == 12
        assert sheet.page_setup.orientation == 'landscape'
        assert 'تحذير الموقع' not in values
    elif name == 'inventory':
        assert '00123' in values and '1234567890123456' in values
        assert 12.3456 in values and -1234.5 in values
        assert 'سرية' not in values
    else:
        assert values.count('مادة أ') == 4
        assert values.count('المادة') == 1
        assert 'الإجمالي: 100000' in values
    results.append(dict(file=path.name, rows=sheet.max_row,
                        columns=sheet.max_column, rtl=True, verified=True))
output = dict(reader=f'openpyxl {openpyxl.__version__}', workbooks=results)
(root / 'validation/xlsx/result.json').write_text(json.dumps(output, indent=2), encoding='utf-8')
print(json.dumps(output, indent=2))
