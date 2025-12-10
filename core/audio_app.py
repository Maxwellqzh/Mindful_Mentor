import os
import numpy as np
import pandas as pd
import librosa
import whisper
import tensorflow as tf

# =========================================================
# 修改点：使用 tf_keras 来加载旧版 Keras 2 的模型
# =========================================================
import tf_keras
from tf_keras.models import model_from_json
from tf_keras.optimizers import RMSprop
# =========================================================

from sklearn.preprocessing import LabelEncoder
from openai import OpenAI
from pathlib import Path

class AudioDialogueSystem:
    def __init__(self, 
                 emotion_model_json='data/emotion/model.json',
                 emotion_model_h5='data/emotion/saved_models/Emotion_Voice_Detection_Model.h5',
                 whisper_size='base',
                 deepseek_api_key="sk-0a9db92f5431452d8ad8fe32c7f9eb8c",
                 device=None):
        """
        初始化音频对话系统，加载所有必要的模型。
        """
        self.device = device
        self.deepseek_api_key = deepseek_api_key or os.getenv("DEEPSEEK_API_KEY")
        
        # 1. 初始化 DeepSeek 客户端
        if self.deepseek_api_key:
            self.llm_client = OpenAI(
                api_key=self.deepseek_api_key,
                base_url="https://api.deepseek.com"
            )
        else:
            print("Warning: DeepSeek API Key 未提供，LLM 对话功能将不可用。")
            self.llm_client = None

        # 2. 加载 Whisper 模型
        print(f"Loading Whisper ({whisper_size})...")
        self.whisper_model = self._load_whisper(whisper_size)
        print("✓ Whisper model loaded")

        # 3. 加载情绪识别模型
        print("Loading Emotion Detection Model...")
        # 强制设置环境变量以确保兼容性
        os.environ["TF_USE_LEGACY_KERAS"] = "1"
        self.emotion_model, self.label_encoder = self._load_emotion_model(emotion_model_json, emotion_model_h5)
        print("✓ Emotion model loaded")

    def _load_whisper(self, size):
        """内部方法：加载 Whisper"""
        import torch
        if self.device is None:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
        return whisper.load_model(size, device=self.device)

    def _load_emotion_model(self, json_path, h5_path):
        """内部方法：使用 tf_keras 加载旧版模型"""
        # 读取 JSON 结构
        with open(json_path, 'r') as json_file:
            loaded_model_json = json_file.read()
        
        # 使用 tf_keras 加载模型结构
        model = model_from_json(loaded_model_json)
        
        # 加载权重
        model.load_weights(h5_path)
        
        # 编译模型
        opt = RMSprop(learning_rate=1e-5)
        model.compile(loss='categorical_crossentropy', optimizer=opt, metrics=['accuracy'])
        
        # 定义标签
        emotion_labels = [
            'female_calm', 'male_calm', 'female_happy', 'male_happy',
            'female_sad', 'male_sad', 'female_angry', 'male_angry',
            'female_fearful', 'male_fearful'
        ]
        lb = LabelEncoder()
        lb.fit(emotion_labels)
        
        return model, lb

    def transcribe(self, audio_path):
        """功能 1: 语音转文本"""
        if not os.path.exists(audio_path):
            return "Error: Audio file not found"
        
        result = self.whisper_model.transcribe(audio_path, language='zh')
        return result["text"].strip()

    def detect_emotion(self, audio_path):
        """功能 2: 语音情绪识别"""
        if not os.path.exists(audio_path):
            return "unknown"

        # 预处理音频：提取 MFCC 特征
        # 严格保持原参数以匹配模型输入
        X, sample_rate = librosa.load(audio_path, res_type='kaiser_fast', duration=2.5, sr=22050 * 2, offset=0.5)
        mfccs = np.mean(librosa.feature.mfcc(y=X, sr=np.array(sample_rate), n_mfcc=13), axis=0)
        
        # 调整数据形状
        livedf2 = pd.DataFrame(data=mfccs)
        livedf2 = livedf2.stack().to_frame().T
        twodim = np.expand_dims(livedf2, axis=2)

        # 推理
        livepreds = self.emotion_model.predict(twodim, batch_size=32, verbose=0)
        livepreds1 = livepreds.argmax(axis=1)
        liveabc = livepreds1.astype(int).flatten()
        prediction = self.label_encoder.inverse_transform(liveabc)
        
        return prediction[0]
    def chat(self, text, emotion_context="neutral"):
            """
            功能 3: LLM 对话 (优化版：平衡内容与情绪)
            """
            if not self.llm_client:
                return "Error: API Key not configured"

            # 优化后的 Prompt：强调内容理解，降低情绪对话题的干扰
            system_prompt = (
                "你是一个温暖、有洞察力的知心朋友（Mindful Mentor）。\n"
                "【当前上下文】\n"
                f"1. 用户输入的语音转文字内容为：{text}\n"
                f"2. 声音检测到的情绪标签为：【{emotion_context}】（注意：声音模型可能会误判，请结合文字内容综合判断）。\n\n"
                "【回复策略】\n"
                "1. **内容优先**：首先理解用户在说什么。如果用户在朗读诗歌、课文或陈述事实（如《静夜思》），请针对内容进行互动（例如讨论诗句、夸奖背诵），不要单纯因为检测到‘生气’就只顾着安抚。\n"
                "2. **纠错能力**：语音识别可能存在同音字错误（如'敬夜司'应为'静夜思'，'第八刻'可能是'第八课'），请自动理解正确的语义，不要被错别字带偏。\n"
                "3. **情感融合**：\n"
                "   - 如果内容是正常的（如背诗），但情绪检测为'angry'，可能是朗读语气较重，请忽略'生气'标签，用赞赏或探讨的语气回复。\n"
                "   - 只有当文字内容明显带有抱怨、发泄且情绪标签也为负面时，才侧重于安抚情绪。\n\n"
                "请给出一个简短、自然、像朋友一样的回复："
            )

            try:
                response = self.llm_client.chat.completions.create(
                    model="deepseek-chat",
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": text}
                    ],
                    temperature=0.7 # 稍微降低一点温度，让逻辑更稳
                )
                return response.choices[0].message.content.strip()
            except Exception as e:
                return f"API Call Failed: {str(e)}"

    def run_pipeline(self, audio_path):
        """运行完整流程"""
        print(f"\n--- Processing Audio: {os.path.basename(audio_path)} ---")
        
        # 1. Get Text
        text = self.transcribe(audio_path)
        print(f"[Text]: {text}")
        
        # 2. Get Emotion
        emotion = self.detect_emotion(audio_path)
        print(f"[Emotion]: {emotion}")
        
        # 3. Get Response
        review = self.chat(text, emotion)
        print(f"[AI Reply]: {review}")
        
        return {
            "text": text,
            "emotion": emotion,
            "response": review
        }

if __name__ == "__main__":
    system = AudioDialogueSystem(whisper_size="base")
    audio_file_1 = 'data/audio/静夜思.mp3' 
    if os.path.exists(audio_file_1):
        system.run_pipeline(audio_file_1)
    else:
        print(f"File not found: {audio_file_1}")