#!/usr/bin/env python3
# Streaming/Dataset capture script for the NeRFCapture iOS App

import argparse
import cv2
from pathlib import Path
import json
import shutil
import sys
import numpy as np
import tyro
import subprocess as sp
import shlex

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
class Params:
	domain_id: int = 0
	verbose: bool = False
	save_path: Path = Path(__file__).parent / "test.mp4"

# DDS
# ==================================================================================================
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

@dataclass
@annotate.final
@annotate.autoid("sequential")
class Pose(idl.IdlStruct, typename="NeRFCaptureData.Pose"):
	id: types.uint32
	annotate.key("id")
	timestamp: types.float64
	fl_x: types.float32
	fl_y: types.float32
	cx: types.float32
	cy: types.float32
	transform_matrix: types.array[types.float32, 16]

@dataclass
@annotate.final
@annotate.autoid("sequential")
class PosedVideoFrame(idl.IdlStruct, typename="NeRFCaptureData.PosedVideoFrame"):
	stream_id: types.uint32
	annotate.key("stream_id")
	timestamp: types.float64
	nalus: types.sequence[types.uint8]
	transform_matrix: types.array[types.float32, 16]
	fl_x: types.float32
	fl_y: types.float32
	cx: types.float32
	cy: types.float32
	width: types.uint32
	height: types.uint32
	has_depth: bool
	depth_zlib: types.sequence[types.uint8]
	depth_width: types.uint32
	depth_height: types.uint32

dds_config = """<?xml version="1.0" encoding="UTF-8" ?> \
<CycloneDDS xmlns="https://cdds.io/config" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd"> \
	<Domain id="any"> \
		<Tracing> \
			<Verbosity>config</Verbosity> \
			<OutputFile>stdout</OutputFile> \
		</Tracing> \
	</Domain> \
</CycloneDDS> \
"""
# ==================================================================================================

if __name__ == "__main__":
	params = tyro.cli(Params)

	# Setup DDS
	domain = Domain(domain_id=params.domain_id, config=dds_config)
	participant = DomainParticipant()
	qos = Qos(Policy.Reliability.Reliable(
		max_blocking_time=duration(seconds=1)))
	video_topic = Topic(participant, "PosedVideo", PosedVideoFrame)
	video_reader = DataReader(participant, video_topic)
	loglevel = "-loglevel quiet" if not params.verbose else ""
	# h265_params="-preset ultrafast -tune zerolatency"
	# x265_params = f'-x265-params "{h265_params}"'
	x265_params = ""
	thread_type = "frame"
	input_pix_fmt="yuv420p" 
	output_pix_fmt="yuv420p"
	encoder="hevc"
	fps = 30
	threads = 2
	file_path = params.save_path

	initialized = False
	counter = 0
	while True:
		sample = video_reader.read_next()
		if sample:
			if not initialized:
				initialized = True
				width = sample.width
				height = sample.height
				print(f"Initializing video writer with width {width} and height {height}")
				writer = sp.Popen(
					shlex.split(f'ffmpeg {loglevel} -y -threads {threads} -thread_type {thread_type} -f hevc -r {fps} -i pipe: -vcodec {encoder} {x265_params} -pix_fmt {output_pix_fmt} {file_path}'), 
					stdout=sp.DEVNULL,
					stdin=sp.PIPE)
			else:
				print(f"Writing frame {counter}")
				counter += 1
				X_WV = np.array(sample.transform_matrix).reshape((4, 4))
				print(X_WV)
				b = bytes(sample.nalus)
				writer.stdin.write(b)
				if counter == 100:
					writer.stdin.close()
					writer.wait()
					break
