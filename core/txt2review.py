"""
txt2review - 将wav2txt生成的文本文件输入DeepSeek API进行评价
"""

import os
import argparse
from pathlib import Path
from typing import Optional, Union

# ============================================================================
# DeepSeek API 配置
# ============================================================================
# 在这里直接填入你的 DeepSeek API 密钥
# 获取API密钥: https://platform.deepseek.com/api_keys
DEEPSEEK_API_KEY = "sk-0a9db92f5431452d8ad8fe32c7f9eb8c"  # TODO: 替换为你的实际API密钥

# DeepSeek API 基础URL（通常不需要修改）
DEEPSEEK_BASE_URL = "https://api.deepseek.com"

# 默认使用的模型
DEFAULT_MODEL = "deepseek-chat"

DEFAULT_REVIEW_PROMPT = """你好！我想和你聊聊天~"""

def get_deepseek_review(
    text_file: Union[str, Path],
    api_key: Optional[str] = DEEPSEEK_API_KEY,
    base_url: Optional[str] = DEEPSEEK_BASE_URL,
    model: Optional[str] = DEFAULT_MODEL,
    review_prompt: Optional[str] = None,
    output_file: Optional[Union[str, Path]] = None
) -> str:
    """
    读取文本文件，调用DeepSeek API进行评价
    
    Args:
        text_file: wav2txt生成的文本文件路径
        api_key: DeepSeek API密钥，如果为None则从环境变量DEEPSEEK_API_KEY读取
        base_url: DeepSeek API的基础URL
        model: 使用的模型名称
        review_prompt: 自定义评价提示词，如果为None则使用默认提示词
        output_file: 输出评价结果的文件路径，如果为None则自动生成
    
    Returns:
        DeepSeek的评价文本
    """
    try:
        from openai import OpenAI
    except ImportError:
        raise ImportError(
            "未安装 openai 库。请运行: pip install openai"
        )
    
    # 读取文本文件
    text_path = Path(text_file)
    if not text_path.exists():
        raise FileNotFoundError(f"文本文件不存在: {text_file}")
    
    with open(text_path, 'r', encoding='utf-8') as f:
        text_content = f.read().strip()
    
    if not text_content:
        raise ValueError("文本文件为空")
    
    print(f"已读取文本文件: {text_path.name}")
    print(f"你说的话预览: {text_content[:100]}...")
    
    # 获取API密钥（优先级：参数 > 文件中的常量 > 环境变量）
    if api_key is None:
        if DEEPSEEK_API_KEY and DEEPSEEK_API_KEY != "your-api-key-here":
            api_key = DEEPSEEK_API_KEY
            print("使用文件中定义的API密钥")
        else:
            api_key = os.getenv("DEEPSEEK_API_KEY")
            if api_key:
                print("使用环境变量中的API密钥")
    
    if not api_key or api_key == "your-api-key-here":
        raise ValueError(
            "未提供API密钥。请选择以下方式之一:\n"
            "1. 在文件中设置 DEEPSEEK_API_KEY 常量（推荐）\n"
            "2. 设置环境变量 DEEPSEEK_API_KEY\n"
            "3. 通过命令行参数 -k/--api-key 提供\n\n"
            "获取API密钥: https://platform.deepseek.com/api_keys"
        )
    
    # 使用默认值（如果未提供）
    if base_url is None:
        base_url = DEEPSEEK_BASE_URL
    if model is None:
        model = DEFAULT_MODEL
    
    # 设置默认提示词（知心朋友聊天风格）
    if review_prompt is None:
        review_prompt = """你好！我想和你聊聊天~

下面这段文字是我刚才说的，通过语音识别转换成了文字。作为一个知心朋友，我想听听你对这段话的想法和感受。

请用知心朋友的语气和我聊天，就像好朋友在听我说话一样：
- 理解我想表达的意思
- 和我聊聊天，说说你的想法
- 可以问我一些问题，继续我们的对话
- 语气要温和、贴心、自然，就像真正的好朋友一样

不需要太正式，就像我们平时聊天那样自然就好~"""
    
    # 构建完整的提示词（把文本当作用户说的话）
    full_prompt = f"{review_prompt}\n\n---\n\n我刚刚说的是：\n{text_content}\n\n---\n\n请用知心朋友的身份和我聊聊吧~"
    
    # 调用DeepSeek API
    print(f"\n正在和知心朋友聊天中... (模型: {model})")
    try:
        client = OpenAI(
            api_key=api_key,
            base_url=base_url
        )
        
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "你是一个温暖、贴心的知心朋友，善于倾听和理解。当朋友通过语音识别向你分享他们说的话时，你会认真倾听，用友好、温和的语气和对方聊天，理解他们的想法，分享你的感受，就像真正的好朋友在轻松愉快地对话一样。你会积极回应，可能会问一些问题来继续对话，让聊天更自然流畅。"},
                {"role": "user", "content": full_prompt}
            ],
            temperature=0.8,  # 稍微提高温度，让回答更自然、更有朋友的感觉
            max_tokens=2000
        )
        
        review_text = response.choices[0].message.content.strip()
        
    except Exception as e:
        raise RuntimeError(
            f"调用DeepSeek API失败: {e}\n\n"
            f"请检查:\n"
            f"1. API密钥是否正确\n"
            f"2. 网络连接是否正常\n"
            f"3. API服务是否可用\n"
            f"获取API密钥: https://platform.deepseek.com/api_keys"
        )
    
    # 保存评价结果
    if output_file is None:
        output_file = text_path.with_suffix('.review.txt')
    else:
        output_file = Path(output_file)
    
    print(f"\n正在保存评价结果到: {output_file}")
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("=" * 60 + "\n")
        f.write("与知心朋友的对话 💙\n")
        f.write("=" * 60 + "\n\n")
        f.write("我说的话:\n")
        f.write("-" * 60 + "\n")
        f.write(text_content + "\n\n")
        f.write("=" * 60 + "\n\n")
        f.write("知心朋友的回应:\n")
        f.write("-" * 60 + "\n")
        f.write(review_text + "\n")
        f.write("-" * 60 + "\n")
        f.write("=" * 60 + "\n")
    
    print(f"✓ 聊天完成！")
    print(f"对话已保存到: {output_file}")
    
    return review_text


def main():
    """命令行接口"""
    parser = argparse.ArgumentParser(
        description='将wav2txt生成的文本文件与DeepSeek知心朋友聊天'
    )
    parser.add_argument(
        'input',
        type=str,
        help='输入的文本文件路径（wav2txt生成的文本文件）'
    )
    parser.add_argument(
        '-o', '--output',
        type=str,
        default=None,
        help='输出评价结果的文件路径（默认: 原文件名.review.txt）'
    )
    parser.add_argument(
        '-k', '--api-key',
        type=str,
        default=None,
        help='DeepSeek API密钥（优先级：参数 > 文件中的常量 > 环境变量）'
    )
    parser.add_argument(
        '--base-url',
        type=str,
        default=None,
        help=f'DeepSeek API基础URL（默认: {DEEPSEEK_BASE_URL}）'
    )
    parser.add_argument(
        '-m', '--model',
        type=str,
        default=None,
        help=f'使用的模型名称（默认: {DEFAULT_MODEL}）'
    )
    parser.add_argument(
        '--custom-prompt',
        type=str,
        default=None,
        help='自定义评价提示词（可选）'
    )
    
    args = parser.parse_args()
    
    input_path = Path(args.input)
    
    if not input_path.exists():
        print(f"错误: 文件不存在: {args.input}")
        return 1
    
    try:
        review = get_deepseek_review(
            input_path,
            api_key=args.api_key,
            base_url=args.base_url,
            model=args.model,
            review_prompt=args.custom_prompt,
            output_file=args.output
        )
        
        print("\n" + "=" * 60)
        print("知心朋友的回应预览:")
        print("=" * 60)
        print(review[:500] + ("..." if len(review) > 500 else ""))
        print("=" * 60)
        
        return 0
        
    except Exception as e:
        print(f"错误: {e}")
        return 1


if __name__ == '__main__':
    exit(main())

