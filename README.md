# NeRF Capture

<img src="docs/assets_readme/NeRFCaptureReal.png" height="342"/><img src="docs/assets_readme/NeRFCaptureSample.gif" height="342"/>


Collecting NeRF datasets is difficult. NeRF Capture is an iOS application that allows any iPhone or iPad to quickly collect or stream posed images to [InstantNGP](https://github.com/NVlabs/instant-ngp). If your device has a LiDAR, the depth images will be saved/streamed as well. The app has two modes: Offline and Online. In Offline mode, the dataset is saved to the device and can be accessed in the Files App in the NeRFCapture folder. Online mode uses [CycloneDDS](https://github.com/eclipse-cyclonedds/cyclonedds) to publish the posed images on the network. A Python script then collects the images and provides them to InstantNGP.

We are working to put the app on the App Store and make the data collection more convenient. Until then, you will need to clone this repo on a Mac with XCode and load it manually into your iOS device.


## Online Mode

<img src="docs/assets_readme/NeRFCaptureScreenshot.png" height="342"/>

Use the Reset button to reset the coordinate system to the current position of the camera. This takes a while; wait until the tracking initialized before moving away.

Switch the app to online mode. On the computer running InstantNGP, make sure that CycloneDDS is installed in the same python environment that is running pyngp. OpenCV and Pillow are needed to save and resize images.

```
pip install cyclonedds
pip install opencv-python
pip install Pillow
```

Check that the computer can see the device on your network by running in your terminal:

```
cyclonedds ps
```

To get started, copy one of the scripts in nerfcapture/scripts to instant_ngp/scripts where pyngp can be imported. Run the script in the same way you would run the run.py that comes with InstantNGP. Wait until NeRFCapture displays that a connection has been established (This can take a few seconds). You can press the Send button to publish the current frame to InstantNGP. You have to press the send button everytime you want to capture another frame. Automatic streaming is not yet enabled. Note that it may take up to half a second for your image to transfer depending on your network.

There are two scripts made available. The first nerfcapture_stream, will build the NeRF with new images while your session is running. The second will simply capture your frames and save them to a dataset. You can then drag that dataset into InstantNGP.

## Offline Mode

In Offline mode, clicking start initializes the dataset. Take a few images then click End when you're done. The dataset can be found as a zip file in your Files App in the format that InstantNGP expects. Unzip the dataset and drag and drop it into InstantNGP. We have found it farely difficult to get files transferred from an iOS device to another computer so we recommend running the app in Online mode and collecting the dataset with the nerfcapture_dataset.py script.

<img src="docs/assets_readme/NeRFCaptureFile1.png" height="342"/>
<img src="docs/assets_readme/NeRFCaptureFile2.png" height="342"/>




