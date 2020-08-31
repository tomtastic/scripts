#!/usr/bin/env python3
''' 20200830 - TRCM - what do ANSI colours look like in this terminal '''
import sys

attr = {
    'All attributes off': '\33[0m',  # (color at startup)
    'Bold on': '\33[1m',  # (enable foreground intensity)
    'Bold off': '\33[21m',  # (disable foreground intensity)
    'Underline on': '\33[4m',
    'Underline off':  '\33[24m',
    'Blink on': '\33[5m',  # (enable background intensity)
    'Blink off': '\33[25m',  # (disable background intensity)
    }
bg = {
    'Default': '\33[49m',  # background colour at startup
    'Black': '\33[40m',
    'Red': '\33[41m',
    'Green': '\33[42m',
    'Yellow': '\33[43m',
    'Blue': '\33[44m',
    'Magenta': '\33[45m',
    'Cyan': '\33[46m',
    'White': '\33[47m',
    'Light Gray': '\33[100m',
    'Light Red': '\33[101m',
    'Light Green': '\33[102m',
    'Light Yellow': '\33[103m',
    'Light Blue': '\33[104m',
    'Light Magenta': '\33[105m',
    'Light Cyan': '\33[106m',
    'Light White': '\33[107m'
    }
fg = {
    'Default': '\33[39m',  # foreground colour at startup
    'Black': '\33[30m',
    'Red': '\33[31m',
    'Green': '\33[32m',
    'Yellow': '\33[33m',
    'Blue': '\33[34m',
    'Magenta': '\33[35m',
    'Cyan': '\33[36m',
    'White': '\33[37m',
    'Light Gray': '\33[90m',
    'Light Red': '\33[91m',
    'Light Green': '\33[92m',
    'Light Yellow': '\33[93m',
    'Light Blue': '\33[94m',
    'Light Magenta': '\33[95m',
    'Light Cyan': '\33[96m',
    'Light White': '\33[97m'
    }

def show(background, foreground):
    ''' print the colour combination '''
    textend = f"{bg['Default']}{fg['Default']}"
    print(f"{bg[background]}{fg[foreground]}{background:>20}",
          f"({repr(bg[background])})",
          " + ",
          f"({repr(fg[foreground])})",
          f"{foreground:<20}",
          textend)

if len(sys.argv) > 1:
    # print the full combination range
    for b in bg:
        for f in fg:
            show(b, f)
else:
    # Just the plain backgrounds
    plain = ['Black', 'Light Gray']
    for b in plain:
        for f in fg:
            show(b, f)
