#!/usr/bin/env python3
"""Import T3 Code and T3 Chat colors from the upstream palette source."""
from pathlib import Path
import re, math, json, sys
root = Path(__file__).resolve().parents[3]
s=(root/'packages/shared/src/themePalettes.ts').read_text()
def palette(section):
 vals=dict(re.findall(r'(\w+): "([^"]+)"',section))
 def rgb(v):
  if v.startswith('#'): return v
  L,C,H=map(float,re.findall(r'[\d.]+',v)); a=C*math.cos(H*math.pi/180); b=C*math.sin(H*math.pi/180)
  l=(L+.3963377774*a+.2158037573*b)**3; m=(L-.1055613458*a-.0638541728*b)**3; z=(L-.0894841775*a-1.291485548*b)**3
  linear=[4.0767416621*l-3.3077115913*m+.2309699292*z,-1.2684380046*l+2.6097574011*m-.3413193965*z,-.0041960863*l-.7034186147*m+1.707614701*z]
  def gamma(x): return 12.92*x if x<=.0031308 else 1.055*max(0,x)**(1/2.4)-.055
  return '#'+''.join(f'{round(max(0,min(1,gamma(x)))*255):02x}' for x in linear)
 return {k:rgb(v) for k,v in vals.items() if v.startswith(('#','oklch'))}
chat=s.split('export const T3_CHAT_THEME:')[1].split('export const GROVE_THEME:')[0]
themes={'t3-code':{'light':palette(s.split('export const T3_CODE_LIGHT_THEME_COLORS')[1].split('export const T3_CODE_DARK_THEME_COLORS')[0]),'dark':palette(s.split('export const T3_CODE_DARK_THEME_COLORS')[1].split('export const T3_CHAT_THEME')[0])},'t3-chat':{'light':palette(chat.split('colors: {')[1].split('variants:')[0]),'dark':palette(chat.split('dark: {')[1])}}
result = json.dumps(themes, indent=2) + "\n"
target = root / "apps/ios-native/App/ThemeColors.json"
if "--check" in sys.argv:
 if target.read_text() != result:
  raise SystemExit("Native theme colors differ from upstream. Run Scripts/sync-theme-colors.py and review the rendered changes.")
 print("PASS: native palette matches upstream theme tokens")
else:
 target.write_text(result)
 print("Updated native theme colors; verify light and dark appearances before committing.")
