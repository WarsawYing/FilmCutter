#!/usr/bin/env python3
"""Minimal regression suite for FilmCutter's TIFF processing contract."""

import os
import sys
import tempfile
import unittest

import numpy as np
import tifffile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine import handle_preview, handle_process
from detectors.v2 import detect_file_v2
from detectors.v2.detector import StripCandidate, _frames_from_strip
from image_reader import read_image
from processor import cut_frames, invert_image


class FilmCutterRegressionTests(unittest.TestCase):
    def test_v2_detects_repeated_135_geometry_without_full_decode(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = os.path.join(temp_dir, "synthetic-135.tif")
            source = np.zeros((660, 1800, 3), dtype=np.uint16)
            rng = np.random.default_rng(42)

            # Two horizontal strips, four 3:2 frames per strip.  Narrow dark
            # separators are retained to exercise strip grouping.
            for strip_y in (30, 350):
                for frame_index in range(4):
                    x0 = 30 + frame_index * 400
                    texture = rng.integers(
                        4000,
                        56000,
                        size=(280, 390, 3),
                        dtype=np.uint16,
                    )
                    source[strip_y:strip_y + 280, x0:x0 + 390] = texture

            tifffile.imwrite(path, source, photometric="rgb")
            result = detect_file_v2(path, format_id="135")

            self.assertEqual(result["frame_count"], 8)
            self.assertEqual(result["strip_count"], 2)
            self.assertTrue(all(frame["width"] > frame["height"]
                                for frame in result["frames"]))

    def test_v2_does_not_fill_a_low_information_film_tail(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = os.path.join(temp_dir, "synthetic-tail.tif")
            source = np.zeros((1800, 700, 3), dtype=np.uint16)
            rng = np.random.default_rng(7)

            # One vertical strip has room for three geometry cells, but only
            # the first two contain photographs.  The last cell is a tail.
            source[:, 170:530] = 5000
            for frame_index in range(2):
                y0 = 25 + frame_index * 580
                texture = rng.integers(
                    6000,
                    52000,
                    size=(550, 330, 3),
                    dtype=np.uint16,
                )
                source[y0:y0 + 550, 185:515] = texture

            tifffile.imwrite(path, source, photometric="rgb")
            result = detect_file_v2(path, format_id="135")

            self.assertEqual(result["frame_count"], 2)
            self.assertEqual(result["strip_count"], 1)

    def test_v2_keeps_low_texture_frame_between_confident_frames(self):
        # Three repeated vertical cells: detailed image, nearly textureless
        # image, detailed image.  The middle cell is still physically inside
        # the occupied roll span and must not be mistaken for a blank tail.
        texture = np.full((420, 100), 0.001, dtype=np.float32)
        texture[6:134, 7:93] = 0.020
        texture[286:414, 7:93] = 0.020
        strip = StripCandidate(
            x=0,
            y=0,
            width=100,
            height=420,
            texture_mean=0.013,
            texture_density=0.66,
        )

        frames = _frames_from_strip(strip, texture)

        self.assertEqual(len(frames), 3)

    def test_v2_sample_135_counts_when_fixture_folder_is_present(self):
        sample_dir = os.path.abspath(os.path.join(
            os.path.dirname(__file__),
            "..",
            "sampleTiffs",
        ))
        expected = {
            "135NegSample1.tif": 12,
            "135NegSample2.tiff": 2,
            "135PosSample1.tiff": 12,
        }
        if not all(os.path.exists(os.path.join(sample_dir, name))
                   for name in expected):
            self.skipTest("optional 135 sample TIFFs are not present")

        for name, frame_count in expected.items():
            with self.subTest(name=name):
                result = detect_file_v2(
                    os.path.join(sample_dir, name),
                    format_id="135",
                )
                self.assertEqual(result["frame_count"], frame_count)
                if name == "135NegSample1.tif":
                    top = result["frames"][:6]
                    bottom = result["frames"][6:]
                    self.assertLess(
                        max(frame["y"] for frame in top),
                        min(frame["y"] for frame in bottom),
                    )
                elif name == "135PosSample1.tiff":
                    left = result["frames"][:6]
                    right = result["frames"][6:]
                    self.assertLess(
                        max(frame["x"] for frame in left),
                        min(frame["x"] for frame in right),
                    )

    def test_reads_rgb16_without_quantizing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = os.path.join(temp_dir, "rgb16.tif")
            source = np.zeros((12, 16, 3), dtype=np.uint16)
            source[:, :, 0] = 1000
            source[:, :, 1] = 30000
            source[:, :, 2] = 60000
            tifffile.imwrite(path, source, photometric="rgb")

            actual, metadata = read_image(path)

            self.assertEqual(actual.dtype, np.uint16)
            self.assertEqual(metadata["bit_depth"], 16)
            np.testing.assert_array_equal(actual, source)

    def test_memory_mapped_read_keeps_uncompressed_scan_disk_backed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = os.path.join(temp_dir, "mapped-rgb16.tif")
            source = np.full((24, 32, 3), 12345, dtype=np.uint16)
            tifffile.imwrite(
                path,
                source,
                photometric="rgb",
                compression=None,
            )

            actual, _ = read_image(path, memory_mapped=True)

            self.assertIsInstance(actual, np.memmap)
            np.testing.assert_array_equal(actual, source)

    def test_normalizes_planar_rgb16_to_height_width_channels(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = os.path.join(temp_dir, "planar-rgb16.tif")
            planar = np.zeros((3, 12, 16), dtype=np.uint16)
            planar[0, :, :] = 1000
            planar[1, :, :] = 30000
            planar[2, :, :] = 60000
            tifffile.imwrite(
                path,
                planar,
                photometric="rgb",
                planarconfig="separate",
            )

            actual, metadata = read_image(path)

            self.assertEqual(actual.shape, (12, 16, 3))
            self.assertEqual(metadata["mode"], "RGB")
            np.testing.assert_array_equal(actual, np.moveaxis(planar, 0, -1))

    def test_rejects_multi_page_tiff_instead_of_dropping_pages(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = os.path.join(temp_dir, "multi-page.tif")
            with tifffile.TiffWriter(path) as writer:
                writer.write(np.zeros((12, 16), dtype=np.uint16))
                writer.write(np.ones((12, 16), dtype=np.uint16))

            with self.assertRaisesRegex(ValueError, "Multi-page TIFF"):
                read_image(path)

    def test_uint16_inversion_preserves_dtype_and_full_range(self):
        source = np.array([[0, 100, 255, 65535]], dtype=np.uint16)

        actual = invert_image(source, {})

        self.assertEqual(actual.dtype, np.uint16)
        np.testing.assert_array_equal(
            actual,
            np.array([[65535, 65435, 65280, 0]], dtype=np.uint16),
        )

    def test_cut_frames_applies_border_and_clamps_to_image(self):
        source = np.arange(20 * 30, dtype=np.uint16).reshape(20, 30)
        frames = [{"x": 5, "y": 6, "width": 10, "height": 8}]

        result = cut_frames(source, frames, {}, border_px=2)[0]

        self.assertEqual((result["x"], result["y"]), (3, 4))
        self.assertEqual((result["width"], result["height"]), (14, 12))
        np.testing.assert_array_equal(result["data"], source[4:16, 3:17])

    def test_process_writes_native_uint16_pixels(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = os.path.join(temp_dir, "source.tif")
            output_dir = os.path.join(temp_dir, "output")
            source = (
                np.arange(20 * 30, dtype=np.uint16).reshape(20, 30) * 100
            )
            tifffile.imwrite(source_path, source)

            response = handle_process({
                "command": "process",
                "files": [source_path],
                "combined_frames": [[{
                    "index": 0,
                    "x": 5,
                    "y": 6,
                    "width": 10,
                    "height": 8,
                }]],
                "output_dir": output_dir,
                "batch_name": "roll_",
                "invert": False,
                "border_px": 2,
            })

            self.assertEqual(response["status"], "complete")
            output = tifffile.imread(response["files"][0])
            self.assertEqual(output.dtype, np.uint16)
            np.testing.assert_array_equal(output, source[4:16, 3:17])

    def test_process_preserves_rgb16_channel_values(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = os.path.join(temp_dir, "source-rgb.tif")
            output_dir = os.path.join(temp_dir, "output")
            source = np.zeros((12, 16, 3), dtype=np.uint16)
            source[:, :, 0] = 1000
            source[:, :, 1] = 30000
            source[:, :, 2] = 60000
            tifffile.imwrite(source_path, source, photometric="rgb")

            response = handle_process({
                "command": "process",
                "files": [source_path],
                "combined_frames": [[{
                    "index": 0,
                    "x": 0,
                    "y": 0,
                    "width": 16,
                    "height": 12,
                }]],
                "output_dir": output_dir,
                "batch_name": "rgb",
                "invert": False,
                "border_px": 0,
            })

            self.assertEqual(response["status"], "complete")
            with tifffile.TiffFile(response["files"][0]) as result:
                self.assertEqual(result.pages[0].photometric.name, "RGB")
                output = result.pages[0].asarray()
            np.testing.assert_array_equal(output, source)

    def test_process_preserves_icc_profile_and_resolution(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = os.path.join(temp_dir, "color-managed.tif")
            output_dir = os.path.join(temp_dir, "output")
            icc_profile = b"FilmCutter synthetic ICC profile"
            source = np.zeros((12, 16, 3), dtype=np.uint16)
            tifffile.imwrite(
                source_path,
                source,
                photometric="rgb",
                resolution=(300, 300),
                resolutionunit="INCH",
                extratags=[(
                    34675,
                    7,
                    len(icc_profile),
                    icc_profile,
                    False,
                )],
            )

            response = handle_process({
                "command": "process",
                "files": [source_path],
                "combined_frames": [[{
                    "index": 0,
                    "x": 0,
                    "y": 0,
                    "width": 16,
                    "height": 12,
                }]],
                "output_dir": output_dir,
                "batch_name": "metadata",
                "invert": False,
                "border_px": 0,
            })

            self.assertEqual(response["status"], "complete")
            with tifffile.TiffFile(response["files"][0]) as result:
                page = result.pages[0]
                self.assertEqual(page.tags[34675].value, icc_profile)
                self.assertEqual(page.tags["XResolution"].value, (300, 1))
                self.assertEqual(page.resolutionunit.name, "INCH")

    def test_process_refuses_to_overwrite_existing_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = os.path.join(temp_dir, "source.tif")
            output_dir = os.path.join(temp_dir, "output")
            os.makedirs(output_dir)
            tifffile.imwrite(
                source_path, np.zeros((20, 30), dtype=np.uint16))
            existing_path = os.path.join(output_dir, "roll_001.tif")
            existing_bytes = b"do not overwrite"
            with open(existing_path, "wb") as existing:
                existing.write(existing_bytes)

            response = handle_process({
                "command": "process",
                "files": [source_path],
                "combined_frames": [[{
                    "index": 0,
                    "x": 1,
                    "y": 1,
                    "width": 10,
                    "height": 10,
                }]],
                "output_dir": output_dir,
                "batch_name": "roll_",
                "invert": False,
                "border_px": 0,
            })

            self.assertEqual(response["status"], "error")
            self.assertIn("already exists", response["error"])
            with open(existing_path, "rb") as existing:
                self.assertEqual(existing.read(), existing_bytes)

    def test_batch_failure_rolls_back_earlier_outputs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            first_path = os.path.join(temp_dir, "first.tif")
            missing_path = os.path.join(temp_dir, "missing.tif")
            output_dir = os.path.join(temp_dir, "output")
            tifffile.imwrite(
                first_path, np.full((20, 30), 1000, dtype=np.uint16))
            frame = {
                "index": 0,
                "x": 2,
                "y": 2,
                "width": 10,
                "height": 10,
            }

            response = handle_process({
                "command": "process",
                "files": [first_path, missing_path],
                "combined_frames": [[frame], [frame]],
                "output_dir": output_dir,
                "batch_name": "rollback",
                "invert": False,
                "border_px": 0,
            })

            self.assertEqual(response["status"], "error")
            self.assertFalse(
                os.path.exists(os.path.join(output_dir, "rollback_001.tif")))
            self.assertFalse(
                os.path.exists(os.path.join(output_dir, "rollback_002.tif")))

    def test_process_rejects_misaligned_batch_lists(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = os.path.join(temp_dir, "source.tif")
            tifffile.imwrite(
                source_path, np.zeros((20, 30), dtype=np.uint16))

            response = handle_process({
                "command": "process",
                "files": [source_path, source_path],
                "combined_frames": [[{
                    "index": 0,
                    "x": 1,
                    "y": 1,
                    "width": 10,
                    "height": 10,
                }]],
                "output_dir": os.path.join(temp_dir, "output"),
                "batch_name": "bad-request",
                "invert": False,
                "border_px": 0,
            })

            self.assertEqual(response["status"], "error")
            self.assertIn("same length", response["error"])

    def test_preview_reports_partial_batch_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = os.path.join(temp_dir, "source.tif")
            missing_path = os.path.join(temp_dir, "missing.tif")
            tifffile.imwrite(
                source_path, np.full((300, 400), 1000, dtype=np.uint16))

            response = handle_preview({
                "command": "preview",
                "files": [source_path, missing_path],
                "format": "auto",
                "border_px": 0,
            })

            self.assertEqual(response["status"], "error")
            self.assertEqual(response["error_code"], "ERR_0007")
            self.assertIn("missing.tif", response["message"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
