#!/usr/bin/env python3
# Streaming script for NeRFCapture iOS App
# This script subscribes to the NeRFCapture frame stream and saves the dataset for offline use

import argparse
from pathlib import Path
from common import *
import pyngp as ngp  # noqa
import cv2
import json
from PIL import Image
import time
import shutil

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

def parse_args():
    parser = argparse.ArgumentParser(description="Run neural graphics primitives testbed with additional configuration & output options")
    parser.add_argument("--n_frames", required=True, type=int, help="Number of frames before saving the dataset")
    parser.add_argument("--save_path", required=True, type=str, help="Path to save the dataset")
    parser.add_argument("--depth_scale", default=1.0, type=str, help="Depth scale used when saving depth")
    parser.add_argument("--override", action="store_true", help="Rewrite over dataset if it exist")
    return parser.parse_args()


def save_frame(testbed, frame_idx: int, rgb: np.ndarray, depth: np.ndarray, depth_scale: float, X_WV: np.ndarray, fx: float, fy: float, cx: float, cy: float): 
    testbed.nerf.training.set_image(frame_idx = frame_idx, img=rgb, depth_img=depth, depth_scale=depth_scale*testbed.nerf.training.dataset.scale)
    testbed.nerf.training.set_camera_extrinsics(frame_idx=frame_idx, camera_to_world=X_WV)
    testbed.nerf.training.set_camera_intrinsics(frame_idx=frame_idx, fx=fx, fy=fy, cx=cx, cy=cy)

if __name__ == "__main__":
    args = parse_args()

    # Check Arguments
    if args.n_frames <= 0:
        raise ValueError("n_frames must be greater than 0")
    
    save_path = Path(args.save_path)
    if save_path.exists():
        if args.override:
            # Prompt user to confirm deletion
            res = input("Warning, directory exists already. Press Y to delete anyway: ")
            if res == 'Y':
                shutil.rmtree(save_path)
            else:
                exit()
        else:
            raise ValueError("save_path already exists")
    
    # Make directory
    images_dir = save_path.joinpath("images")

    # Setup DDS
    domain = Domain(domain_id=0, config=dds_config)
    participant = DomainParticipant()
    qos = Qos(Policy.Reliability.Reliable(
        max_blocking_time=duration(seconds=1)))
    topic = Topic(participant, "Frames", NeRFCaptureFrame, qos=qos)
    reader = DataReader(participant, topic)

    manifest = {
        "fl_x":  0.0,
        "fl_y":  0.0,
        "cx": 0.0, 
        "cy": 0.0,
        "w": 0.0,
        "h": 0.0,
        "frames": []
    }

    total_frames = 0 # Total frames received

    # Start DDS Loop
    while True:
        time.sleep(0.001)
        sample = reader.read_next() # Get frame from NeRFCapture
        if sample:
            print(f"Frame received")

            if total_frames == 0:
                save_path.mkdir(parents=True)
                images_dir.mkdir()
                manifest["w"] = sample.width
                manifest["h"] = sample.height
                manifest["cx"] = sample.cx
                manifest["cy"] = sample.cy
                manifest["fl_x"] = sample.fl_x
                manifest["fl_y"] = sample.fl_y
                manifest["integer_depth_scale"] = args.depth_scale/65535.0

            # RGB
            image = np.asarray(sample.image, dtype=np.uint8).reshape(
                (sample.height, sample.width, 3))
            image = np.concatenate(
                [image, 255*np.ones((sample.height, sample.width, 1), dtype=np.uint8)], axis=-1)
            Image.fromarray(image).save(images_dir.joinpath(f"{total_frames}.png"))

            # Depth if avaiable
            depth = None
            if sample.has_depth:
                depth = np.asarray(sample.depth_image, dtype=np.uint8).view(
                    dtype=np.float32).reshape((sample.depth_height, sample.depth_width))
                depth = (depth*65535/float(args.depth_scale)).astype(np.uint16)
                depth = cv2.resize(depth, dsize=(
                    sample.width, sample.height), interpolation=cv2.INTER_NEAREST)
                Image.fromarray(depth).save(images_dir.joinpath(f"{total_frames}.depth.png"))


            # Transform
            X_WV = np.asarray(sample.transform_matrix,
                              dtype=np.float32).reshape((4, 4)).T

            
            frame = {
                "transform_matrix": X_WV.tolist(),
                "file_path": f"images/{total_frames}",
                "fl_x": sample.fl_x,
                "fl_y": sample.fl_y,
                "cx": sample.cx,
                "cy": sample.cy,
                "w": sample.width,
                "h": sample.height
            }

            if depth is not None:
                frame["depth_path"] = f"images/{total_frames}.depth.png"

            manifest["frames"].append(frame)

            # Update index
            total_frames += 1
            if total_frames == args.n_frames:
                # Write manifest as json
                manifest_json = json.dumps(manifest, indent=4)
                with open(save_path.joinpath("transforms.json"), "w") as f:
                    f.write(manifest_json)
                exit()


            
