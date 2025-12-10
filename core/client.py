# client.py
import requests
import sys
import json
import argparse

def main():
    # 设置命令行参数，让你可以通过命令行传入文件路径
    parser = argparse.ArgumentParser(description="音频对话客户端")
    parser.add_argument("audio_path", help="要处理的音频文件路径 (例如: data/audio/test.mp3)")
    args = parser.parse_args()

    # 服务器地址
    url = "http://127.0.0.1:8000/process"
    
    # 构造请求数据
    payload = {
        "audio_path": args.audio_path
    }

    print(f"正在发送请求: {args.audio_path} ...")
    
    try:
        # 发送 POST 请求给一直运行的 server
        response = requests.post(url, json=payload)
        
        if response.status_code == 200:
            data = response.json()
            print("\n" + "="*30)
            print("【服务端返回结果】")
            print(f"识别文本: {data.get('text')}")
            print(f"检测情绪: {data.get('emotion')}")
            print("-" * 30)
            print(f"AI 回复: {data.get('response')}")
            print("="*30 + "\n")
        else:
            print(f"错误: {response.status_code} - {response.text}")
            
    except requests.exceptions.ConnectionError:
        print("无法连接到服务器。请确认 server.py 是否正在后台运行。")

if __name__ == "__main__":
    main()