import json

import numpy as np

from PROJECT.ethernet_fft import app
from PROJECT.ethernet_fft.app import capture_headless, write_capture_evidence
from PROJECT.ethernet_fft.receiver import ReceiverStats
from PROJECT.tests.test_lab_console_model import make_response


class _FixtureReceiver:
    def __init__(self, frame_ids: list[int], stats: ReceiverStats) -> None:
        self._responses = [
            make_response(np.zeros(2048, dtype=np.uint64), frame_id=frame_id)
            for frame_id in frame_ids
        ]
        self.stats = stats

    def frames(self, *, limit: int, stop, on_idle):
        completed = 0
        for response in self._responses:
            if limit and completed >= limit:
                return
            completed += 1
            yield response
            if stop is not None and stop(response):
                return
        if on_idle is not None:
            on_idle()


def test_headless_capture_reports_frame_and_transport_counters() -> None:
    receiver = _FixtureReceiver(
        [41, 42, 43],
        ReceiverStats(
            packets_received=36,
            completed_frames=3,
            lost_frames=1,
            invalid_datagrams=2,
            duplicate_chunks=3,
            out_of_order_chunks=4,
        ),
    )

    result = capture_headless(
        receiver,
        frame_limit=3,
        duration_seconds=0,
        clock=iter([10.0, 12.5]).__next__,
    )

    assert result == {
        "requested_frames": 3,
        "duration_seconds": 0,
        "elapsed_seconds": 2.5,
        "stop_reason": "frame_limit",
        "completed_frames": 3,
        "first_frame_id": 41,
        "last_frame_id": 43,
        "frame_id_span": 2,
        "packets_received": 36,
        "lost_frames": 1,
        "invalid_datagrams": 2,
        "duplicate_chunks": 3,
        "out_of_order_chunks": 4,
    }


def test_headless_capture_stops_on_duration_before_an_unbounded_stream() -> None:
    receiver = _FixtureReceiver(
        [10, 11, 12],
        ReceiverStats(24, 3, 0, 0, 0, 0),
    )

    result = capture_headless(
        receiver,
        frame_limit=0,
        duration_seconds=5,
        clock=iter([100.0, 101.0, 106.0, 106.0]).__next__,
    )

    assert result["stop_reason"] == "duration"
    assert result["completed_frames"] == 2
    assert result["first_frame_id"] == 10
    assert result["last_frame_id"] == 11


def test_capture_evidence_is_json_with_a_versioned_schema(tmp_path) -> None:
    capture = {
        "requested_frames": 150,
        "duration_seconds": 0,
        "elapsed_seconds": 12.5,
        "stop_reason": "frame_limit",
        "completed_frames": 150,
        "first_frame_id": 1,
        "last_frame_id": 150,
        "frame_id_span": 149,
        "packets_received": 1800,
        "lost_frames": 0,
        "invalid_datagrams": 0,
        "duplicate_chunks": 0,
        "out_of_order_chunks": 0,
    }

    evidence_path = write_capture_evidence(
        capture, evidence_dir=tmp_path, captured_at="2026-07-31T12:00:00Z"
    )

    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    assert evidence_path.name == "axu4ev-ad9364-ethernet-capture-20260731T120000Z.json"
    assert evidence == {
        "schema_version": 1,
        "captured_at_utc": "2026-07-31T12:00:00Z",
        **capture,
    }


def test_main_headless_writes_evidence_and_prints_acceptance_summary(
    monkeypatch, tmp_path, capsys
) -> None:
    class FixtureReceiver(_FixtureReceiver):
        def __init__(self, **_kwargs) -> None:
            super().__init__([1, 2], ReceiverStats(24, 2, 0, 0, 0, 0))

        def __enter__(self):
            return self

        def __exit__(self, *_exc_info) -> None:
            return None

    monkeypatch.setattr(app, "UdpFftReceiver", FixtureReceiver)

    assert app.main(
        [
            "--headless",
            "--frames",
            "2",
            "--bind",
            "127.0.0.1",
            "--evidence-dir",
            str(tmp_path),
        ]
    ) == 0

    evidence_paths = list(tmp_path.glob("axu4ev-ad9364-ethernet-capture-*.json"))
    assert len(evidence_paths) == 1
    assert json.loads(evidence_paths[0].read_text(encoding="utf-8"))["last_frame_id"] == 2
    assert "ETH_FFT: PASS frames=2 last_frame=2 lost_frames=0 invalid_datagrams=0" in capsys.readouterr().out
