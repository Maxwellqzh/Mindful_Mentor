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
                 device='cuda'):
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

        # 4. [新增] 初始化对话记忆
        self.history = [] 
        # 设置系统人设（仅在初始化时设置一次，作为历史的第一条）
        self.system_prompt_content = (
            "你是一个温暖、有洞察力的知心朋友（Mindful Mentor）。\n"
            "回复策略：\n"
            "1. 内容优先：如果用户在朗读或陈述事实，请针对内容互动，不要被单一的情绪标签误导。\n"
            "2. 纠错能力：请自动理解语音识别可能产生的同音错别字。\n"
            "3. 情感融合：仅当文字内容和情绪标签同时为负面时，才侧重安抚；否则以自然交流为主。\n"
            "请保持回复简短自然。"
        )
        self.reset_history() # 初始化历史

    def reset_history(self):
        """[新增] 清空对话历史，重置为仅包含 System Prompt"""
        self.history = [
            {"role": "system", "content": self.system_prompt_content}
        ]
        print("--- Memory Reset ---")

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
        """功能 2: 语音情绪识别 (修复版：增加形状检查与填充)"""
        if not os.path.exists(audio_path):
            return "unknown"

        try:
            # 1. 加载音频
            # 注意：duration=2.5 是指"最多"加载2.5秒，如果文件短，它只会加载实际长度
            X, sample_rate = librosa.load(audio_path, res_type='kaiser_fast', duration=2.5, sr=22050 * 2, offset=0.5)
            
            # 安全检查：如果音频极短或加载失败
            if len(X) == 0:
                print("Warning: Audio file is too short or empty.")
                return "neutral" # 返回一个默认情绪

            # 2. 提取 MFCC 特征
            mfccs = np.mean(librosa.feature.mfcc(y=X, sr=np.array(sample_rate), n_mfcc=13), axis=0)
            
            # ================= 关键修复开始 =================
            # 强制将特征长度统一为 216
            target_length = 216
            current_length = len(mfccs)

            if current_length < target_length:
                # 情况 A: 录音太短 -> 补零 (Padding)
                pad_width = target_length - current_length
                mfccs = np.pad(mfccs, (0, pad_width), mode='constant')
            elif current_length > target_length:
                # 情况 B: 录音太长 -> 截断 (Truncate)
                mfccs = mfccs[:target_length]
            
            # 此时 len(mfccs) 必定是 216
            # ================= 关键修复结束 =================

            # 3. 调整数据形状以适配模型 (Batch, TimeSteps, 1)
            livedf2 = pd.DataFrame(data=mfccs)
            livedf2 = livedf2.stack().to_frame().T
            twodim = np.expand_dims(livedf2, axis=2)

            # 4. 推理
            livepreds = self.emotion_model.predict(twodim, batch_size=32, verbose=0)
            livepreds1 = livepreds.argmax(axis=1)
            liveabc = livepreds1.astype(int).flatten()
            prediction = self.label_encoder.inverse_transform(liveabc)
            
            return prediction[0]

        except Exception as e:
            print(f"Emotion Detection Error: {e}")
            return "neutral" # 出错时返回默认值，防止程序崩溃

    def chat(self, text, emotion_context="neutral"):
        """
        功能 3: LLM 对话 (修改版：带有记忆功能)
        """
        if not self.llm_client:
            return "Error: API Key not configured"

        # 构造当前的用户输入，带上情绪上下文
        current_input_content = (
            f"【用户语音内容】：{text}\n"
            f"【检测到的情绪】：{emotion_context}"
        )

        # [新增] 将当前轮次的用户消息追加到历史
        self.history.append({"role": "user", "content": current_input_content})

        # [可选] 打印当前的 Token 消耗提示（防止历史过长）
        # print(f"Current history length: {len(self.history)} messages")

        try:
            response = self.llm_client.chat.completions.create(
                model="deepseek-chat",
                # [关键修改] 这里不再是发送单条，而是发送整个 self.history
                messages=self.history,
                temperature=0.7 
            )
            
            reply_text = response.choices[0].message.content.strip()

            # [新增] 将 AI 的回复也追加到历史，形成闭环
            self.history.append({"role": "assistant", "content": reply_text})

            return reply_text
        except Exception as e:
            # 如果报错，把刚才加进去的用户消息移除，防止坏死循环
            self.history.pop()
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
    
    # --- 模拟多轮对话测试记忆 ---
    
    # 第 1 轮：假设这是自我介绍
    # 你可以把 audio_file_1 换成一段说 "你好，我叫小明" 的音频
    audio_file_1 = 'data/audio/intro.mp3' 
    if os.path.exists(audio_file_1):
        system.run_pipeline(audio_file_1)
    
    # 第 2 轮：假设这是在问 "我刚才说我叫什么？"
    # 此时 AI 应该能从 self.history 中找到第 1 轮的信息并回答 "你叫小明"
    audio_file_2 = 'data/audio/question.mp3'
    if os.path.exists(audio_file_2):
        system.run_pipeline(audio_file_2)