import os
import numpy as np
import pandas as pd
import librosa
import whisper 
import tensorflow as tf
import tf_keras
from tf_keras.models import model_from_json
from tf_keras.optimizers import RMSprop
from sklearn.preprocessing import LabelEncoder
from openai import OpenAI
from pathlib import Path

class AudioDialogueSystem:
    def __init__(self, 
                 emotion_model_json='data/emotion/model.json',
                 emotion_model_h5='data/emotion/saved_models/Emotion_Voice_Detection_Model.h5',
                 whisper_size='small', 
                 deepseek_api_key="sk-0a9db92f5431452d8ad8fe32c7f9eb8c",
                 device='cuda'):
        
        self.device = device
        self.deepseek_api_key = deepseek_api_key or os.getenv("DEEPSEEK_API_KEY")
        
        # 1. 初始化 DeepSeek
        if self.deepseek_api_key:
            self.llm_client = OpenAI(
                api_key=self.deepseek_api_key,
                base_url="https://api.deepseek.com"
            )
        else:
            self.llm_client = None

        # 2. 加载 Whisper 模型 (本地加载)
        model_path = "core/models/small.pt" 
        print(f"Loading OpenAI Whisper from local: {model_path} ...")
        
        if os.path.exists(model_path):
            self.whisper_model = whisper.load_model(model_path, device=self.device)
        else:
            print(f"Warning: 本地模型 {model_path} 不存在，尝试自动下载...")
            self.whisper_model = whisper.load_model(whisper_size, device=self.device)
        print("✓ Whisper model loaded")

        # 3. 加载情绪识别模型
        print("Loading Emotion Detection Model...")
        os.environ["TF_USE_LEGACY_KERAS"] = "1"
        self.emotion_model, self.label_encoder = self._load_emotion_model(emotion_model_json, emotion_model_h5)
        print("✓ Emotion model loaded")

        # 4. 初始化记忆 & 设置更丰富的人设
        self.history = [] 
        
        # ================= 修改点：更丰富、多元的 System Prompt =================
        self.system_prompt_content = (
            "你是一位名为 Mindful Mentor 的资深心理咨询师和知心朋友。你的性格温暖、包容、富有同理心。\n"
            "你的任务是根据用户的话语内容和情绪状态，提供有深度、多元化的回应。\n\n"
            "回复指导原则：\n"
            "1. 【深度共情】：不要只停留在表面，尝试解读用户话语背后的潜台词和情感需求。\n"
            "2. 【多元视角】：不要只给一句简单的安慰。可以结合心理学知识、生活哲学或具体的行动建议来丰富你的回答。\n"
            "3. 【情绪整合】：如果用户说的话是开心的，但情绪标签是悲伤的，请敏锐地指出这种矛盾，并温柔地询问原因。\n"
            "4. 【引导式提问】：在回复的最后，适当地抛出一个开放式问题，引导用户多说一些，帮助他们宣泄情绪。\n"
            "5. 【语言风格】：请使用温暖、治愈的口吻，避免说教。回复长度适中，不要太短，确保能把问题说透。\n"
        )
        # ===================================================================
        
        self.reset_history()

    def reset_history(self):
        self.history = [{"role": "system", "content": self.system_prompt_content}]
        print("--- Memory Reset ---")

    def _load_emotion_model(self, json_path, h5_path):
        with open(json_path, 'r') as json_file:
            loaded_model_json = json_file.read()
        model = model_from_json(loaded_model_json)
        model.load_weights(h5_path)
        opt = RMSprop(learning_rate=1e-5)
        model.compile(loss='categorical_crossentropy', optimizer=opt, metrics=['accuracy'])
        emotion_labels = [
            'female_calm', 'male_calm', 'female_happy', 'male_happy',
            'female_sad', 'male_sad', 'female_angry', 'male_angry',
            'female_fearful', 'male_fearful'
        ]
        lb = LabelEncoder()
        lb.fit(emotion_labels)
        return model, lb

    def transcribe(self, audio_path):
        """功能 1: 语音转文本 (强制简体中文)"""
        if not os.path.exists(audio_path):
            return "Error: Audio file not found"
        
        # ================= 修改点：加入 initial_prompt 强制简体 =================
        # initial_prompt 就像给模型一个“开头”，模型会模仿这个开头的语言风格
        result = self.whisper_model.transcribe(
            audio_path, 
            language='zh', 
            fp16=False,
            initial_prompt="以下是普通话的句子，请用简体中文转录。" 
        )
        # ===================================================================
        
        return result["text"].strip()

    def detect_emotion(self, audio_path):
        """功能 2: 语音情绪识别"""
        if not os.path.exists(audio_path): return "unknown"
        try:
            X, sample_rate = librosa.load(audio_path, res_type='kaiser_fast', duration=2.5, sr=22050 * 2, offset=0.5)
            if len(X) == 0: return "neutral"
            
            mfccs = np.mean(librosa.feature.mfcc(y=X, sr=np.array(sample_rate), n_mfcc=13), axis=0)
            
            # 形状修正
            target_length = 216
            current_length = len(mfccs)
            if current_length < target_length:
                mfccs = np.pad(mfccs, (0, target_length - current_length), mode='constant')
            elif current_length > target_length:
                mfccs = mfccs[:target_length]
                
            livedf2 = pd.DataFrame(data=mfccs).stack().to_frame().T
            twodim = np.expand_dims(livedf2, axis=2)
            
            livepreds = self.emotion_model.predict(twodim, batch_size=32, verbose=0)
            livepreds1 = livepreds.argmax(axis=1)
            prediction = self.label_encoder.inverse_transform(livepreds1.astype(int).flatten())
            return prediction[0]
        except Exception as e:
            print(f"Emotion Error: {e}")
            return "neutral"

    def chat(self, text, emotion_context="neutral"):
        if not self.llm_client: return "Error: API Key missing"
        
        current_input = f"【用户语音】：{text}\n【情绪】：{emotion_context}"
        self.history.append({"role": "user", "content": current_input})

        try:
            response = self.llm_client.chat.completions.create(
                model="deepseek-chat",
                messages=self.history,
                temperature=0.7 
            )
            reply = response.choices[0].message.content.strip()
            self.history.append({"role": "assistant", "content": reply})
            return reply
        except Exception as e:
            self.history.pop()
            return f"API Error: {str(e)}"

    def run_pipeline(self, audio_path):
        print(f"\n--- Processing: {os.path.basename(audio_path)} ---")
        text = self.transcribe(audio_path)
        print(f"[Text]: {text}")
        emotion = self.detect_emotion(audio_path)
        print(f"[Emotion]: {emotion}")
        review = self.chat(text, emotion)
        print(f"[Reply]: {review}")
        return {"text": text, "emotion": emotion, "response": review}