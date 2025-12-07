import os
import librosa
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import tensorflow as tf
from matplotlib.pyplot import specgram
from keras.utils import to_categorical
from sklearn.utils import shuffle
from keras.models import Sequential
from keras.models import model_from_json
from sklearn.preprocessing import LabelEncoder
from keras.optimizers import RMSprop
import argparse

def load_emotion_model(model_json_path='data/emotion/model.json', weights_path='data/emotion/saved_models/Emotion_Voice_Detection_Model.h5'):
    """
    加载预训练的情绪识别模型
    
    Args:
        model_json_path: 模型结构JSON文件路径
        weights_path: 模型权重文件路径
    
    Returns:
        model: 加载好的Keras模型
        lb: 训练好的标签编码器
    """
    # 加载数据用于训练标签编码器
    # 清理 Keras/TensorFlow 会话，防止重复加载模型时出现图或资源冲突
    try:
        tf.keras.backend.clear_session()
    except Exception:
        pass
    mylist = os.listdir(r'C:\ScottDocs\Codes\mindful_mentor\data\emotion\RawData')
    
    feeling_list = []
    for item in mylist:
        if item[6:-16] == '02' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_calm')
        elif item[6:-16] == '02' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_calm')
        elif item[6:-16] == '03' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_happy')
        elif item[6:-16] == '03' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_happy')
        elif item[6:-16] == '04' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_sad')
        elif item[6:-16] == '04' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_sad')
        elif item[6:-16] == '05' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_angry')
        elif item[6:-16] == '05' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_angry')
        elif item[6:-16] == '06' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_fearful')
        elif item[6:-16] == '06' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_fearful')
        elif item[:1] == 'a':
            feeling_list.append('male_angry')
        elif item[:1] == 'f':
            feeling_list.append('male_fearful')
        elif item[:1] == 'h':
            feeling_list.append('male_happy')
        elif item[:2] == 'sa':
            feeling_list.append('male_sad')
    
    labels = pd.DataFrame(feeling_list)
    
    # 训练标签编码器
    lb = LabelEncoder()
    lb.fit(labels.values.ravel())
    
    # 加载模型
    # 使用 with 确保文件正确关闭
    with open(model_json_path, 'r') as json_file:
        loaded_model_json = json_file.read()
    loaded_model = model_from_json(loaded_model_json)
    loaded_model.load_weights(weights_path)
    
    # 编译模型
    opt = RMSprop(learning_rate=1e-5)
    loaded_model.compile(loss='categorical_crossentropy', optimizer=opt, metrics=['accuracy'])
    
    return loaded_model, lb


def extract_audio_features(audio_path, duration=2.5, sr=22050*2, offset=0.5):
    """
    从音频文件中提取MFCC特征
    
    Args:
        audio_path: 音频文件路径
        duration: 音频片段时长
        sr: 采样率
        offset: 开始提取的偏移时间
    
    Returns:
        features: 提取的特征
    """
    X, sample_rate = librosa.load(audio_path, res_type='kaiser_fast', duration=duration, sr=sr, offset=offset)
    mfccs = np.mean(librosa.feature.mfcc(y=X, sr=sample_rate, n_mfcc=13), axis=0)

    # 转换为 DataFrame 格式并处理为模型输入格式
    livedf2 = pd.DataFrame(data=mfccs)
    livedf2 = livedf2.stack().to_frame().T
    twodim = np.expand_dims(livedf2, axis=2)

    # 目标帧长度：模型训练时使用的时间步长（来自模型结构），
    # 如果你的模型期望不同的长度，请调整这个常量。
    TARGET_FRAMES = 216

    # twodim 形状应为 (1, T, 1)，对 T 轴做填充或截断以匹配模型输入
    if twodim.shape[1] < TARGET_FRAMES:
        pad_width = TARGET_FRAMES - twodim.shape[1]
        pad = np.zeros((1, pad_width, 1))
        twodim = np.concatenate([twodim, pad], axis=1)
    elif twodim.shape[1] > TARGET_FRAMES:
        twodim = twodim[:, :TARGET_FRAMES, :]

    return twodim


def predict_emotion(audio_path, model, lb):
    """
    预测音频的情绪
    
    Args:
        audio_path: 音频文件路径
        model: 训练好的模型
        lb: 标签编码器
    
    Returns:
        prediction: 预测的情绪标签
    """
    # 提取特征
    features = extract_audio_features(audio_path)
    
    # 预测
    preds = model.predict(features, batch_size=32, verbose=1)
    pred_class = preds.argmax(axis=1)
    pred_class = pred_class.astype(int).flatten()
    
    # 转换回原始标签
    prediction = lb.inverse_transform(pred_class)
    
    return prediction


def analyze_emotion(audio_path, 
                    model_path=r'C:\ScottDocs\Codes\mindful_mentor\data\emotion\model.json', 
                    weights_path=r'C:\ScottDocs\Codes\mindful_mentor\data\emotion\saved_models\Emotion_Voice_Detection_Model.h5'):  
    """
    分析音频文件的情绪
    
    Args:
        audio_path: 音频文件路径
        model_path: 模型结构文件路径
        weights_path: 模型权重文件路径
    
    Returns:
        emotion: 识别出的情绪
    """
    # 检查文件是否存在
    if not os.path.exists(audio_path):
        raise FileNotFoundError(f"音频文件不存在: {audio_path}")
    
    # 加载模型和编码器
    print("加载情绪识别模型...")
    model, lb = load_emotion_model(model_path, weights_path)
    print("模型加载完成")
    
    # 预测情绪
    print(f"分析音频文件: {audio_path}")
    emotion = predict_emotion(audio_path, model, lb)
    
    return emotion

def emotion_get(audio_path_emotion):
    """
    原始的情绪识别函数，保持向后兼容性
    
    Args:
        audio_path_emotion: 音频文件路径
    
    Returns:
        livepredictions: 预测的情绪标签
    """
    mylist = os.listdir('data/emotion/RawData/')

    feeling_list = []
    for item in mylist:
        if item[6:-16] == '02' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_calm')
        elif item[6:-16] == '02' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_calm')
        elif item[6:-16] == '03' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_happy')
        elif item[6:-16] == '03' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_happy')
        elif item[6:-16] == '04' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_sad')
        elif item[6:-16] == '04' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_sad')
        elif item[6:-16] == '05' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_angry')
        elif item[6:-16] == '05' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_angry')
        elif item[6:-16] == '06' and int(item[18:-4]) % 2 == 0:
            feeling_list.append('female_fearful')
        elif item[6:-16] == '06' and int(item[18:-4]) % 2 == 1:
            feeling_list.append('male_fearful')
        elif item[:1] == 'a':
            feeling_list.append('male_angry')
        elif item[:1] == 'f':
            feeling_list.append('male_fearful')
        elif item[:1] == 'h':
            feeling_list.append('male_happy')
        # elif item[:1]=='n':
        # feeling_list.append('neutral')
        elif item[:2] == 'sa':
            feeling_list.append('male_sad')

    labels = pd.DataFrame(feeling_list)

    df = pd.DataFrame(columns=['feature'])
    bookmark = 0
    for index, y in enumerate(mylist):
        if mylist[index][6:-16] != '01' and mylist[index][6:-16] != '07' and mylist[index][6:-16] != '08' and mylist[index][
                                                                                                              :2] != 'su' and \
                mylist[index][:1] != 'n' and mylist[index][:1] != 'd':
            X, sample_rate = librosa.load('data/emotion/RawData/' + y, res_type='kaiser_fast', duration=2.5, sr=22050 * 2, offset=0.5)
            sample_rate = np.array(sample_rate)
            mfccs = np.mean(librosa.feature.mfcc(y=X,
                                                 sr=sample_rate,
                                                 n_mfcc=13),
                            axis=0)
            feature = mfccs
            # [float(i) for i in feature]
            # feature1=feature[:135]
            df.loc[bookmark] = [feature]
            bookmark = bookmark + 1

    df3 = pd.DataFrame(df['feature'].values.tolist())

    newdf = pd.concat([df3, labels], axis=1)

    rnewdf = newdf.rename(index=str, columns={"0": "label"})

    rnewdf = shuffle(newdf)

    rnewdf = rnewdf.fillna(0)

    newdf1 = np.random.rand(len(rnewdf)) < 0.8
    train = rnewdf[newdf1]
    test = rnewdf[~newdf1]

    trainfeatures = train.iloc[:, :-1]

    trainlabel = train.iloc[:, -1:]

    testfeatures = test.iloc[:, :-1]

    testlabel = test.iloc[:, -1:]

    X_train = np.array(trainfeatures)
    y_train = np.array(trainlabel)
    X_test = np.array(testfeatures)
    y_test = np.array(testlabel)

    lb = LabelEncoder()
    y_train = y_train.ravel()
    y_test = y_test.ravel()
    y_train = to_categorical(lb.fit_transform(y_train))
    y_test = to_categorical(lb.transform(y_test))

    x_traincnn = np.expand_dims(X_train, axis=2)
    x_testcnn = np.expand_dims(X_test, axis=2)

    # loading json and creating model
    # 清理 Keras/TensorFlow 会话，防止重复加载模型时出现图或资源冲突
    try:
        tf.keras.backend.clear_session()
    except Exception:
        pass

    # 使用 with 确保文件正确关闭
    with open('data/emotion/model.json', 'r') as json_file:
        loaded_model_json = json_file.read()
    loaded_model = model_from_json(loaded_model_json)
    # load weights into new model
    loaded_model.load_weights("data/emotion/saved_models/Emotion_Voice_Detection_Model.h5")
    print("Loaded model from disk")

    # evaluate loaded model on test data
    opt = RMSprop(learning_rate=1e-5)
    loaded_model.compile(loss='categorical_crossentropy', optimizer=opt, metrics=['accuracy'])
    score = loaded_model.evaluate(x_testcnn, y_test, verbose=0)
    print("%s: %.2f%%" % (loaded_model.metrics_names[1], score[1] * 100))

    preds = loaded_model.predict(x_testcnn,
                                 batch_size=32,
                                 verbose=1)

    preds1 = preds.argmax(axis=1)

    abc = preds1.astype(int).flatten()

    predictions = (lb.inverse_transform((abc)))

    preddf = pd.DataFrame({'predictedvalues': predictions})

    actual = y_test.argmax(axis=1)
    abc123 = actual.astype(int).flatten()
    actualvalues = (lb.inverse_transform((abc123)))

    actualdf = pd.DataFrame({'actualvalues': actualvalues})

    data, sampling_rate = librosa.load(audio_path_emotion)

    plt.figure(figsize=(15, 5))
    # librosa.display.waveshow(data, sr=sampling_rate)

    # livedf= pd.DataFrame(columns=['feature'])
    X, sample_rate = librosa.load(audio_path_emotion, res_type='kaiser_fast', duration=2.5, sr=22050 * 2, offset=0.5)
    sample_rate = np.array(sample_rate)
    mfccs = np.mean(librosa.feature.mfcc(y=X, sr=sample_rate, n_mfcc=13), axis=0)
    featurelive = mfccs
    livedf2 = featurelive

    livedf2 = pd.DataFrame(data=livedf2)
    livedf2 = livedf2.stack().to_frame().T
    twodim = np.expand_dims(livedf2, axis=2)

    # 确保 live 输入与训练时的时间步长一致
    TARGET_FRAMES = 216
    if twodim.shape[1] < TARGET_FRAMES:
        pad_width = TARGET_FRAMES - twodim.shape[1]
        pad = np.zeros((1, pad_width, 1))
        twodim = np.concatenate([twodim, pad], axis=1)
    elif twodim.shape[1] > TARGET_FRAMES:
        twodim = twodim[:, :TARGET_FRAMES, :]

    livepreds = loaded_model.predict(twodim,
                                     batch_size=32,
                                     verbose=1)

    livepreds1 = livepreds.argmax(axis=1)

    liveabc = livepreds1.astype(int).flatten()

    livepredictions = (lb.inverse_transform((liveabc)))
    return livepredictions

# 添加命令行接口
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='音频情绪识别工具')
    parser.add_argument('audio_file', help='要分析的音频文件路径')
    parser.add_argument('--model', default=r'C:\ScottDocs\Codes\mindful_mentor\data\emotion\model.json', help='模型结构文件路径')
    parser.add_argument('--weights', default=r'C:\ScottDocs\Codes\mindful_mentor\data\emotion\saved_models\Emotion_Voice_Detection_Model.h5', help='模型权重文件路径')
    parser.add_argument('--output', '-o', help='输出结果文件路径（可选）')
    
    args = parser.parse_args()
    
    try:
        # 使用新的分析函数
        emotion = analyze_emotion(args.audio_file, args.model, args.weights)
        
        # 输出结果
        result = f"识别到的情绪: {emotion[0]}"
        print(result)
        
        # 如果指定了输出文件，保存结果
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(result + '\n')
            print(f"结果已保存到: {args.output}")
            sys.exit(0)
    
    except Exception as e:
        print(f"分析过程中出错: {str(e)}")
        import sys
        sys.exit(1)