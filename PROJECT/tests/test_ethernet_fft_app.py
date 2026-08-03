import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from PROJECT.ethernet_fft import app
from PROJECT.ethernet_fft.app import LiveSpectrumView, _argument_parser
from PROJECT.ethernet_fft.receiver import ReceiverStats
from PROJECT.tests.test_lab_console_model import make_response


def test_parser_defaults_to_truly_continuous_capture() -> None:
    args = _argument_parser().parse_args([])

    assert args.bind == "192.168.1.100"
    assert args.port == 5005
    assert args.frames == 0
    assert args.history == 32


def test_live_view_updates_one_line_and_keeps_only_32_frames() -> None:
    view = LiveSpectrumView(history=32)
    line = view.spectrum_line
    try:
        for frame_id in range(1, 151):
            spectrum = np.zeros(2048, dtype=np.uint64)
            spectrum[20] = frame_id
            view.accept_response(
                make_response(spectrum, frame_id=frame_id, peak_bin=20),
                ReceiverStats(
                    packets_received=frame_id * 12,
                    completed_frames=frame_id,
                    lost_frames=2,
                    invalid_datagrams=3,
                    duplicate_chunks=4,
                    out_of_order_chunks=5,
                ),
                fps=12.5,
            )

        assert view.spectrum_line is line
        assert len(view.history) == 32
        assert view.history.frames[-1].response.frame_id == 150
        status = view.status_text.get_text()
        assert "frame 150" in status
        assert "peak bin 20" in status
        assert "2400.300000 MHz" in status
        assert "12.5 FPS" in status
        assert "lost 2" in status
        assert "invalid 3" in status
        assert "out-of-order 5" in status
        assert "packets 1800" in status
    finally:
        plt.close(view.figure)


def test_negative_frame_limit_is_rejected_by_parser() -> None:
    parser = _argument_parser()

    try:
        parser.parse_args(["--frames", "-1"])
    except SystemExit as exc:
        assert exc.code == 2
    else:
        raise AssertionError("negative --frames must be rejected")


def test_main_treats_keyboard_interrupt_as_a_clean_stop(monkeypatch) -> None:
    class InterruptedReceiver:
        def __init__(self, **_kwargs) -> None:
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_exc_info) -> None:
            pass

        def frames(self, **_kwargs):
            raise KeyboardInterrupt
            yield

    monkeypatch.setattr(app, "UdpFftReceiver", InterruptedReceiver)
    monkeypatch.setattr(app.plt, "show", lambda **_kwargs: None)

    assert app.main(["--bind", "127.0.0.1", "--frames", "1"]) == 0


def test_main_services_window_close_during_network_idle(monkeypatch) -> None:
    class IdleReceiver:
        def __init__(self, **_kwargs) -> None:
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_exc_info) -> None:
            pass

        def frames(self, *, limit, stop, on_idle):
            del limit, stop
            assert on_idle() is True
            return
            yield

    monkeypatch.setattr(app, "UdpFftReceiver", IdleReceiver)
    monkeypatch.setattr(app.plt, "show", lambda **_kwargs: None)
    monkeypatch.setattr(app.plt, "pause", lambda _seconds: plt.close("all"))

    assert app.main(["--bind", "127.0.0.1"]) == 0
