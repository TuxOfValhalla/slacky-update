#!/usr/bin/env python3
# --- [ STATIC ICON ASSET GENERATOR ] ---

import os
import sys
from PyQt5.QtWidgets import QApplication
from PyQt5.QtGui import QPixmap, QPainter, QColor, QBrush, QPen, QFont, QPainterPath, QImage
from PyQt5.QtCore import Qt, QRectF

app = QApplication(sys.argv)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
DEST_DIR = os.path.join(REPO_ROOT, "assets")
os.makedirs(DEST_DIR, exist_ok=True)

SRC_ICON = os.path.join(DEST_DIR, "slackware_tight2.png")
if not os.path.exists(SRC_ICON):
    SRC_ICON = "/home/tux/Pictures/icons/slackware_tight2.png"

img = QImage(SRC_ICON)
if not img.isNull():
    base_pixmap = QPixmap.fromImage(img)
else:
    base_pixmap = QPixmap(SRC_ICON)
if base_pixmap.isNull():
    base_pixmap = QPixmap(128, 128)
    base_pixmap.fill(Qt.transparent)
    painter = QPainter(base_pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(QBrush(QColor(0, 43, 85)))
    painter.setPen(QPen(QColor(255, 255, 255), 4))
    painter.drawEllipse(4, 4, 120, 120)
    painter.setFont(QFont("sans-serif", 64, QFont.Bold))
    painter.setPen(QPen(QColor(255, 255, 255)))
    painter.drawText(QRectF(4, 4, 120, 120), Qt.AlignCenter, "S")
    painter.end()

base_pixmap.scaled(128, 128, Qt.KeepAspectRatio, Qt.SmoothTransformation).save(os.path.join(DEST_DIR, "slacky-update.png"), "PNG")

def make_icon(state):
    pm = base_pixmap.scaled(128, 128, Qt.KeepAspectRatio, Qt.SmoothTransformation)
    painter = QPainter(pm)
    painter.setRenderHint(QPainter.Antialiasing)
    
    badge_size = 64
    x = 128 - badge_size - 4
    y = 128 - badge_size - 4
    cx = x + (badge_size / 2.0)
    cy = y + (badge_size / 2.0)

    if state == "ok":
        painter.setBrush(QBrush(QColor(16, 185, 129)))
        painter.setPen(QPen(QColor(255, 255, 255), 4))
        painter.drawEllipse(QRectF(x, y, badge_size, badge_size))

        painter.setPen(QPen(QColor(255, 255, 255), 5.5, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        painter.setBrush(Qt.NoBrush)
        check_path = QPainterPath()
        check_path.moveTo(cx - 15, cy + 1)
        check_path.lineTo(cx - 5, cy + 12)
        check_path.lineTo(cx + 15, cy - 12)
        painter.drawPath(check_path)

    elif state == "pending":
        painter.setBrush(QBrush(QColor(220, 38, 38)))
        painter.setPen(QPen(QColor(255, 255, 255), 4))
        painter.drawEllipse(QRectF(x, y, badge_size, badge_size))

        painter.setBrush(QBrush(QColor(255, 255, 255)))
        painter.setPen(Qt.NoPen)
        arrow_path = QPainterPath()
        arrow_path.moveTo(cx, cy + 17)
        arrow_path.lineTo(cx - 16, cy + 1)
        arrow_path.lineTo(cx - 7, cy + 1)
        arrow_path.lineTo(cx - 7, cy - 17)
        arrow_path.lineTo(cx + 7, cy - 17)
        arrow_path.lineTo(cx + 7, cy + 1)
        arrow_path.lineTo(cx + 16, cy + 1)
        arrow_path.closeSubpath()
        painter.drawPath(arrow_path)

    elif state == "checking":
        # Neutral dark badge with crisp dual arrows: Red UP ⬆️ and Green DOWN ⬇️
        painter.setBrush(QBrush(QColor(30, 41, 59)))
        painter.setPen(QPen(QColor(255, 255, 255), 4))
        painter.drawEllipse(QRectF(x, y, badge_size, badge_size))

        painter.setPen(Qt.NoPen)

        # 1. Left Arrow: Green DOWN ⬇️
        painter.setBrush(QBrush(QColor(34, 197, 94)))
        lx = cx - 11
        down_arrow = QPainterPath()
        down_arrow.moveTo(lx, cy + 14)
        down_arrow.lineTo(lx - 9, cy + 2)
        down_arrow.lineTo(lx - 4, cy + 2)
        down_arrow.lineTo(lx - 4, cy - 14)
        down_arrow.lineTo(lx + 4, cy - 14)
        down_arrow.lineTo(lx + 4, cy + 2)
        down_arrow.lineTo(lx + 9, cy + 2)
        down_arrow.closeSubpath()
        painter.drawPath(down_arrow)

        # 2. Right Arrow: Red UP ⬆️
        painter.setBrush(QBrush(QColor(239, 68, 68)))
        rx = cx + 11
        up_arrow = QPainterPath()
        up_arrow.moveTo(rx, cy - 14)
        up_arrow.lineTo(rx - 9, cy - 2)
        up_arrow.lineTo(rx - 4, cy - 2)
        up_arrow.lineTo(rx - 4, cy + 14)
        up_arrow.lineTo(rx + 4, cy + 14)
        up_arrow.lineTo(rx + 4, cy - 2)
        up_arrow.lineTo(rx + 9, cy - 2)
        up_arrow.closeSubpath()
        painter.drawPath(up_arrow)

    painter.end()
    pm.save(os.path.join(DEST_DIR, f"slacky-update-{state}.png"), "PNG")

make_icon("ok")
make_icon("pending")
make_icon("checking")
