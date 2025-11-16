import librosa
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from matplotlib.pyplot import specgram
from keras.utils import to_categorical
import pandas as pd
import librosa
import matplotlib.pyplot as plt
import numpy as np
import os
from sklearn.utils import shuffle
from tensorflow.keras.utils import to_categorical
from sklearn.preprocessing import LabelEncoder
from keras.models import model_from_json
from tensorflow.keras.optimizers import RMSprop

def emotion_get(audio_path_emotion):
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

    json_file = open('data/emotion/model.json', 'r')
    loaded_model_json = json_file.read()
    json_file.close()
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

    livepreds = loaded_model.predict(twodim,
                                     batch_size=32,
                                     verbose=1)

    livepreds1 = livepreds.argmax(axis=1)

    liveabc = livepreds1.astype(int).flatten()

    livepredictions = (lb.inverse_transform((liveabc)))
    return livepredictions
