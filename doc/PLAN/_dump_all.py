# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding='utf-8')
from docx import Document

d = Document(r'd:\code2\hardware\Structure\final\doc\PLAN\终期报告.docx')
for i, p in enumerate(d.paragraphs):
    t = p.text.strip()
    if t:
        print(f"{i:3d}|{t}")
