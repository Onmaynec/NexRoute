from pathlib import Path

path = Path('tests/NextInterface.Tests.ps1')
text = path.read_text(encoding='utf-8-sig')
replacements = {
    '$common | Should -Match [regex]::Escape("\'>[+]\'" )': '$common | Should -Match ([regex]::Escape("\'>[+]\'"))',
    '($network + $serviceNetwork) | Should -Match ([regex]::Escape($token))': '($common + $network + $serviceNetwork) | Should -Match ([regex]::Escape($token))',
}
for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'Expected one match, got {count}: {old}')
    text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8', newline='\n')
