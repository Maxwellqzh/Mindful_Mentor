# server.py
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import os

# 导入你原本的类
from audio_app import AudioDialogueSystem

app = FastAPI()

# 定义全局变量，用于存储加载后的系统实例
dialogue_system = None

# 定义请求的数据格式
class AudioRequest(BaseModel):
    audio_path: str

@app.on_event("startup")
def startup_event():
    """
    服务器启动时执行：只加载一次模型
    """
    global dialogue_system
    print("正在初始化系统，加载模型中，请稍候...")
    # 这里可以根据需要调整参数
    dialogue_system = AudioDialogueSystem(whisper_size="small")
    print("模型加载完毕，服务已就绪！")

@app.post("/process")
def process_audio(request: AudioRequest):
    """
    接收客户端请求的接口
    """
    if not dialogue_system:
        raise HTTPException(status_code=500, detail="系统尚未初始化")
    
    if not os.path.exists(request.audio_path):
        raise HTTPException(status_code=404, detail=f"找不到文件: {request.audio_path}")

    try:
        # 调用你原来类中的主流程
        result = dialogue_system.run_pipeline(request.audio_path)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    # 启动服务器，监听 8000 端口
    uvicorn.run(app, host="127.0.0.1", port=8000)