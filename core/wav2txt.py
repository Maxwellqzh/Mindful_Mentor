"""
wav2txt - 音频转文本模块
支持使用 Whisper 将音频文件（WAV、MP3、M4A、FLAC、OGG 等）转换为文本文件
"""

import os
import argparse
import subprocess
from pathlib import Path
from typing import Optional, Union


def transcribe_audio(
    audio_file: Union[str, Path],
    output_file: Optional[Union[str, Path]] = None,
    model_name: str = "base",
    language: Optional[str] = None,
    device: Optional[str] = None
) -> str:
    """
    将音频文件转换为文本
    
    Args:
        audio_file: 输入的音频文件路径（支持 wav, mp3, m4a 等格式）
        output_file: 输出文本文件路径，如果为 None 则自动生成
        model_name: Whisper 模型名称，可选：tiny, base, small, medium, large
        language: 音频语言代码（如 'zh', 'en'），None 表示自动检测
        device: 设备类型（'cpu' 或 'cuda'），None 表示自动选择
    
    Returns:
        转换后的文本字符串
    """
    try:
        import whisper
    except ImportError:
        raise ImportError(
            "未安装 whisper 库。请运行: pip install openai-whisper"
        )
    
    # 检查输入文件是否存在
    audio_path = Path(audio_file)
    if not audio_path.exists():
        raise FileNotFoundError(f"音频文件不存在: {audio_file}")
    
    # 检测和设置设备
    if device is None:
        try:
            import torch
            if torch.cuda.is_available():
                device = "cuda"
                print(f"✓ 检测到CUDA，GPU加速已启用 (设备: {torch.cuda.get_device_name(0)})")
            else:
                device = "cpu"
                print("✓ 使用CPU模式")
        except Exception:
            device = "cpu"
            print("⚠ PyTorch检测失败，使用CPU模式")
    elif device == "cuda":
        try:
            import torch
            if not torch.cuda.is_available():
                print("⚠ CUDA不可用，自动切换到CPU模式")
                device = "cpu"
            else:
                print(f"✓ 使用GPU加速 (设备: {torch.cuda.get_device_name(0)})")
        except Exception:
            print("⚠ CUDA检测失败，自动切换到CPU模式")
            device = "cpu"
    
    # 加载 Whisper 模型，处理可能的DLL错误
    print(f"正在加载 Whisper 模型: {model_name}...")
    try:
        model = whisper.load_model(model_name, device=device)
    except OSError as e:
        error_str = str(e)
        if "DLL" in error_str or "动态链接库" in error_str or "WinError" in error_str:
            print("\n⚠ 检测到PyTorch DLL加载错误...")
            
            if device == "cuda":
                print("\nGPU版本PyTorch DLL加载失败。解决方案:")
                print("1. 安装匹配的PyTorch GPU版本:")
                print("   pip uninstall torch torchvision torchaudio")
                print("   pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118")
                print("   (根据你的CUDA版本选择: cu118, cu121, cu124等)")
                print("\n2. 或安装Visual C++ Redistributable:")
                print("   https://aka.ms/vs/17/release/vc_redist.x64.exe")
            
            # 尝试切换到CPU模式
            print("\n正在尝试切换到CPU模式...")
            try:
                import os
                os.environ['CUDA_VISIBLE_DEVICES'] = ''
                model = whisper.load_model(model_name, device="cpu")
                print("✓ 已切换到CPU模式，继续处理...")
            except Exception as e2:
                raise RuntimeError(
                    f"PyTorch DLL加载完全失败。\n\n"
                    f"GPU版本修复:\n"
                    f"  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118\n\n"
                    f"或使用CPU版本:\n"
                    f"  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu\n\n"
                    f"原始错误: {e}"
                )
        else:
            raise
    
    # 检查 ffmpeg 是否可用（Whisper需要ffmpeg处理音频）
    def check_ffmpeg():
        """检查ffmpeg是否在系统PATH中"""
        try:
            result = subprocess.run(
                ['ffmpeg', '-version'],
                capture_output=True,
                timeout=5,
                text=True
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            return False
    
    if not check_ffmpeg():
        raise RuntimeError(
            "未找到 ffmpeg。Whisper需要ffmpeg来处理音频文件。\n\n"
            "请安装 ffmpeg:\n"
            "1. Windows (使用conda，推荐):\n"
            "   conda install -c conda-forge ffmpeg\n\n"
            "2. Windows (使用chocolatey):\n"
            "   choco install ffmpeg\n\n"
            "3. Windows (手动安装):\n"
            "   下载: https://www.gyan.dev/ffmpeg/builds/\n"
            "   解压后将bin目录添加到系统PATH环境变量\n\n"
            "4. 或者使用Anaconda Prompt:\n"
            "   conda install ffmpeg\n\n"
            "安装后请重启终端或IDE，然后重试。"
        )
    
    # 转录音频
    print(f"正在转录音频文件: {audio_path.name}...")
    try:
        result = model.transcribe(
            str(audio_path),
            language=language,
            verbose=False
        )
    except FileNotFoundError as e:
        if "ffmpeg" in str(e).lower() or "系统找不到指定的文件" in str(e):
            raise RuntimeError(
                f"ffmpeg未找到或无法访问。\n\n"
                f"错误: {e}\n\n"
                f"解决方案:\n"
                f"1. 使用conda安装（推荐）:\n"
                f"   conda install -c conda-forge ffmpeg\n\n"
                f"2. 手动下载并添加到PATH:\n"
                f"   https://www.gyan.dev/ffmpeg/builds/\n\n"
                f"3. 安装后重启终端/IDE"
            )
        else:
            raise
    except Exception as e:
        error_str = str(e)
        if "WinError 2" in error_str or "系统找不到指定的文件" in error_str:
            raise RuntimeError(
                f"系统找不到指定的文件（可能是ffmpeg）。\n\n"
                f"错误: {e}\n\n"
                f"请安装ffmpeg:\n"
                f"  conda install -c conda-forge ffmpeg\n"
                f"或访问: https://www.gyan.dev/ffmpeg/builds/"
            )
        raise
    
    # 获取转录文本
    text = result["text"].strip()
    
    # 确定输出文件路径
    if output_file is None:
        output_file = audio_path.with_suffix('.txt')
    else:
        output_file = Path(output_file)
    
    # 保存文本到文件
    print(f"正在保存文本到: {output_file}")
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(text)
    
    print(f"转换完成！")
    print(f"输出文件: {output_file}")
    
    return text


def batch_transcribe(
    audio_dir: Union[str, Path],
    output_dir: Optional[Union[str, Path]] = None,
    model_name: str = "base",
    language: Optional[str] = None,
    audio_extensions: tuple = ('.wav', '.mp3', '.m4a', '.flac', '.ogg')
) -> dict:
    """
    批量转换目录中的音频文件
    
    Args:
        audio_dir: 包含音频文件的目录
        output_dir: 输出文本文件的目录，如果为 None 则在原目录生成
        model_name: Whisper 模型名称
        language: 音频语言代码
        audio_extensions: 支持的音频文件扩展名
    
    Returns:
        转换结果字典，键为音频文件路径，值为文本内容
    """
    audio_dir = Path(audio_dir)
    if not audio_dir.is_dir():
        raise NotADirectoryError(f"目录不存在: {audio_dir}")
    
    if output_dir is None:
        output_dir = audio_dir
    else:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
    
    # 查找所有音频文件
    audio_files = [
        f for f in audio_dir.iterdir()
        if f.is_file() and f.suffix.lower() in audio_extensions
    ]
    
    if not audio_files:
        print(f"在 {audio_dir} 中未找到音频文件")
        return {}
    
    print(f"找到 {len(audio_files)} 个音频文件")
    
    results = {}
    for i, audio_file in enumerate(audio_files, 1):
        print(f"\n处理文件 {i}/{len(audio_files)}: {audio_file.name}")
        try:
            output_file = output_dir / audio_file.with_suffix('.txt').name
            text = transcribe_audio(
                audio_file,
                output_file,
                model_name=model_name,
                language=language
            )
            results[str(audio_file)] = text
        except Exception as e:
            print(f"处理 {audio_file.name} 时出错: {e}")
            results[str(audio_file)] = None
    
    return results


def main():
    """命令行接口"""
    parser = argparse.ArgumentParser(
        description='将音频文件（WAV、MP3、M4A 等）转换为文本文件'
    )
    parser.add_argument(
        'input',
        type=str,
        help='输入的音频文件路径或目录路径'
    )
    parser.add_argument(
        '-o', '--output',
        type=str,
        default=None,
        help='输出文本文件路径（单文件）或输出目录路径（批量处理）'
    )
    parser.add_argument(
        '-m', '--model',
        type=str,
        default='base',
        choices=['tiny', 'base', 'small', 'medium', 'large'],
        help='Whisper 模型大小（默认: base）'
    )
    parser.add_argument(
        '-l', '--language',
        type=str,
        default=None,
        help='音频语言代码（如 zh, en），None 表示自动检测'
    )
    parser.add_argument(
        '-d', '--device',
        type=str,
        default=None,
        choices=['cpu', 'cuda'],
        help='设备类型（cpu 或 cuda），None 表示自动选择'
    )
    parser.add_argument(
        '--batch',
        action='store_true',
        help='批量处理目录中的所有音频文件'
    )
    
    args = parser.parse_args()
    
    input_path = Path(args.input)
    
    try:
        if args.batch or input_path.is_dir():
            # 批量处理模式
            batch_transcribe(
                input_path,
                args.output,
                model_name=args.model,
                language=args.language
            )
        else:
            # 单文件处理模式
            transcribe_audio(
                input_path,
                args.output,
                model_name=args.model,
                language=args.language,
                device=args.device
            )
    except Exception as e:
        print(f"错误: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    exit(main())

