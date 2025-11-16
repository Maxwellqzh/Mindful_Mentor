"""
main.py - 主程序入口
根据wav_path依次调用wav2txt和txt2review完成音频到对话的完整流程
"""

# -*- coding: utf-8 -*-
import sys
from pathlib import Path
from typing import Optional

# 导入模块
from wav2txt import transcribe_audio
from txt2review import get_deepseek_review
from wav2emotion import emotion_get

audio_path = 'data/audio/静夜思.mp3'
text_path = 'data/text/text.txt'
review_path = 'data/text/review.txt'
audio_path_emotion = 'data/emotion/output10.wav'

def main():

    text = transcribe_audio(audio_path,output_file=text_path,language='zh')

    print(text)

    review = get_deepseek_review(text_path,output_file=review_path,model='deepseek-chat')

    print(review)

    emotion = emotion_get(audio_path_emotion)
    print(emotion)

if __name__ == "__main__":
    main()