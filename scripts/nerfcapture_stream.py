#!/usr/bin/env python3
# Streaming script for NeRFCapture iOS App

from common import *
import pyngp as ngp  # noqa
import cv2

import cyclonedds.idl as idl
import cyclonedds.idl.annotations as annotate
import cyclonedds.idl.types as types
from dataclasses import dataclass
from cyclonedds.domain import DomainParticipant, Domain
from cyclonedds.core import Qos, Policy
from cyclonedds.sub import DataReader
from cyclonedds.topic import Topic
from cyclonedds.util import duration

@dataclass
@annotate.final
@annotate.autoid("sequential")
class NeRFCaptureFrame(idl.IdlStruct, typename="NeRFCaptureData.NeRFCaptureFrame"):
    id: types.uint32
    annotate.key("id")
    timestamp: types.float64
    fl_x: types.float32
    fl_y: types.float32
    cx: types.float32
    cy: types.float32
    transform_matrix: types.array[types.float32, 16]
    width: types.uint32
    height: types.uint32
    image: types.sequence[types.uint8]
    has_depth: bool
    depth_width: types.uint32
    depth_height: types.uint32
    depth_scale: types.float32
    depth_image: types.sequence[types.uint8]


dds_config = """<?xml version="1.0" encoding="UTF-8" ?> \
<CycloneDDS xmlns="https://cdds.io/config" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd"> \
    <Domain id="any"> \
        <Internal> \
            <MinimumSocketReceiveBufferSize>10MB</MinimumSocketReceiveBufferSize> \
        </Internal> \
        <Tracing> \
            <Verbosity>config</Verbosity> \
            <OutputFile>stdout</OutputFile> \
        </Tracing> \
    </Domain> \
</CycloneDDS> \
"""

def set_frame(testbed, frame_idx: int, rgb: np.ndarray, depth: np.ndarray, depth_scale: float, X_WV: np.ndarray, fx: float, fy: float, cx: float, cy: float): 
    testbed.nerf.training.set_image(frame_idx = frame_idx, img=rgb, depth_img=depth, depth_scale=depth_scale*testbed.nerf.training.dataset.scale)
    testbed.nerf.training.set_camera_extrinsics(frame_idx=frame_idx, camera_to_world=X_WV)
    testbed.nerf.training.set_camera_intrinsics(frame_idx=frame_idx, fx=fx, fy=fy, cx=cx, cy=cy)

if __name__ == "__main__":

    # Setup DDS
    domain = Domain(domain_id=0, config=dds_config)
    participant = DomainParticipant()
    qos = Qos(Policy.Reliability.Reliable(
        max_blocking_time=duration(seconds=1)))
    topic = Topic(participant, "Frames", NeRFCaptureFrame, qos=qos)
    reader = DataReader(participant, topic)


    # Start InstantNGP
    testbed = ngp.Testbed(ngp.TestbedMode.Nerf)
    testbed.init_window(640, 480)
    testbed.reload_network_from_file(f"configs/nerf/base.json")
    testbed.visualize_unit_cube = True
    testbed.nerf.visualize_cameras = True

    max_cameras = 100  # Maximum number of frames to hold
    camera_index = 0  # Current camera index we are replacing in InstantNGP 
    total_frames = 0 # Total frames received

    # Create Empty Dataset
    testbed.create_empty_nerf_dataset(
        max_cameras, aabb_scale=1)  # , nerf_scale=1/1)
    testbed.nerf.training.n_images_for_training = 0
    testbed.up_dir = np.array([1.0, 0.0, 0.0])

    # Start InstantNGP and DDS Loop
    while testbed.frame():
        sample = reader.read_next() # Get frame from NeRFCapture
        if sample:
            print(f"Frame received")

            # RGB
            image = np.asarray(sample.image, dtype=np.uint8).reshape(
                (sample.height, sample.width, 3)).astype(np.float32)/255.0
            image = np.concatenate(
                [image, np.zeros((sample.height, sample.width, 1), dtype=np.float32)], axis=-1)

            # Depth if avaiable
            depth = None
            if sample.has_depth:
                depth = np.asarray(sample.depth_image, dtype=np.uint8).view(
                    dtype=np.float32).reshape((sample.depth_height, sample.depth_width))
                depth = cv2.resize(depth, dsize=(
                    sample.width, sample.height), interpolation=cv2.INTER_NEAREST)


            # Transform
            X_WV = np.asarray(sample.transform_matrix,
                              dtype=np.float32).reshape((4, 4)).T[:3, :]

            # Add frame to InstantNGP
            set_frame(testbed,
                      frame_idx=camera_index,
                      rgb=srgb_to_linear(image),
                      depth=depth,
                      depth_scale=1,
                      X_WV=X_WV,
                      fx=sample.fl_x,
                      fy=sample.fl_y,
                      cx=sample.cx,
                      cy=sample.cy)

            # Update index
            total_frames += 1
            testbed.nerf.training.n_images_for_training = min(total_frames, max_cameras) 
            camera_index = (camera_index + 1) % max_cameras

            if total_frames == 1:
                testbed.first_training_view()
                testbed.render_groundtruth = True
            
