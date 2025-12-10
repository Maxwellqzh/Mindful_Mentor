import uvicorn
import shutil
import os
# 设置 Hugging Face 镜像地址 (使用国内学术镜像)
os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"
from fastapi import FastAPI, UploadFile, File, HTTPException
from audio_app import AudioDialogueSystem

app = FastAPI()

# 全局变量
dialogue_system = None

@app.on_event("startup")
def startup_event():
    global dialogue_system
    print(">>> 正在初始化系统，加载模型中...")
    # 只需要加载一次，之后一直驻留内存
    dialogue_system = AudioDialogueSystem(whisper_size="small")
    print(">>> 模型加载完毕，服务已就绪！可以开始对话了。")

@app.post("/chat")  # 注意：这里路径名最好和 Flutter 里的对应，比如叫 /chat
async def chat_endpoint(file: UploadFile = File(...)):
    """
    修改点：使用 UploadFile 接收文件流，而不是接收路径字符串
    """
    if not dialogue_system:
        raise HTTPException(status_code=500, detail="系统尚未初始化")

    # 1. 定义一个临时文件名
    temp_filename = f"temp_{file.filename}"
    
    try:
        # 2. 把上传上来的文件字节流，保存到 Python 当前目录
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        print(f"--- 收到音频，正在处理: {temp_filename} ---")

        # 3. 调用你的核心逻辑 (传入本地临时文件的路径)
        result = dialogue_system.run_pipeline(temp_filename)
        
        # result 格式应该是: {"text": "...", "emotion": "...", "response": "..."}
        return result

    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
        
    finally:
        # 4. 清理垃圾：处理完后把临时音频删掉
        if os.path.exists(temp_filename):
            os.remove(temp_filename)
            print("--- 临时文件已清理 ---")

@app.get("/reset")
def reset_endpoint():
    """
    新增功能：重置对话记忆
    """
    if dialogue_system:
        dialogue_system.reset_history()
        return {"status": "Memory reset successfully"}
    return {"status": "System not initialized"}

if __name__ == "__main__":
    # 建议 host 设为 0.0.0.0，这样如果用手机测试也能连上电脑 IP
    uvicorn.run(app, host="0.0.0.0", port=8000)