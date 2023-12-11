# NeRF Capture 
<img src="docs/assets_readme/NeRFCaptureReal.png" height="342"/><img src="docs/assets_readme/NeRFCaptureSample.gif" height="342"/> 


Collecting NeRF datasets is difficult. NeRF Capture is an iOS application that allows any iPhone or iPad to quickly collect or stream posed images to [InstantNGP](https://github.com/NVlabs/instant-ngp). If your device has a LiDAR, the depth images will be saved/streamed as well. The app has two modes: Offline and Online. In Offline mode, the dataset is saved to the device and can be accessed in the Files App in the NeRFCapture folder. Online mode uses [CycloneDDS](https://github.com/eclipse-cyclonedds/cyclonedds) to publish the posed images on the network. A Python script then collects the images and provides them to InstantNGP.

<a href="https://apps.apple.com/us/app/nerfcapture/id6446518379?itsct=apps_box_badge&amp;itscg=30200" style="display: inline-block; overflow: hidden; border-radius: 13px; width: 150px; height: 53px;"><img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83&amp;releaseDate=1679443200" alt="Download on the App Store" style="border-radius: 13px; width: 150px; height: 53px;"></a>



## Online Mode

<img src="docs/assets_readme/NeRFCaptureScreenshot.png" height="342"/>

Use the Reset button to reset the coordinate system to the current position of the camera. This takes a while; wait until the tracking initialized before moving away.

Switch the app to online mode. On the computer running InstantNGP, make sure that CycloneDDS is installed in the same python environment that is running pyngp. OpenCV and Pillow are needed to save and resize images.

```
pip install cyclonedds
```

Check that the computer can see the device on your network by running in your terminal:

```
cyclonedds ps
```

Instructions found in [here](https://github.com/NVlabs/instant-ngp/blob/master/docs/nerf_dataset_tips.md#NeRFCapture)


## Offline Mode

In Offline mode, clicking start initializes the dataset. Take a few images then click End when you're done. The dataset can be found as a zip file in your Files App in the format that InstantNGP expects. Unzip the dataset and drag and drop it into InstantNGP. We have found it farely difficult to get files transferred from an iOS device to another computer so we recommend running the app in Online mode and collecting the dataset with the nerfcapture2nerf.py script found in InstantNGP.

<img src="docs/assets_readme/NeRFCaptureFile1.png" height="342"/>
<img src="docs/assets_readme/NeRFCaptureFile2.png" height="342"/>

## Citation

If you use this software in your research, please consider citing it. 
```bibtex
@misc{
  NeRFCapture,
  url={https://github.com/jc211/NeRFCapture},
  journal={NeRFCapture},
  author={Abou-Chakra, Jad},
  year={2023},
  month={Mar}
} 
```


