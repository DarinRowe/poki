use crate::{Result, Touch};
use idevice::core_device::hid::{
    TOUCHSCREEN_STATE_CONTACT, TOUCHSCREEN_STATE_RELEASE, TouchscreenContact,
};
use std::time::Duration;
use tokio::time::{Instant, sleep_until};

pub(crate) trait TouchSender {
    async fn send_touchscreen(&mut self, state: u8, x: u16, y: u16) -> Result<()>;
    async fn send_multitouch(&mut self, contacts: &[TouchscreenContact]) -> Result<()>;
}

impl TouchSender for Touch {
    async fn send_touchscreen(&mut self, state: u8, x: u16, y: u16) -> Result<()> {
        self.send_touchscreen(state, x, y, None).await?;
        Ok(())
    }
    async fn send_multitouch(&mut self, contacts: &[TouchscreenContact]) -> Result<()> {
        self.send_multitouch(contacts, None).await?;
        Ok(())
    }
}

pub(crate) struct Drag {
    pub x1: u16,
    pub y1: u16,
    pub x2: u16,
    pub y2: u16,
    pub duration_ms: u64,
    pub hold_ms: u64,
    pub end_hold_ms: u64,
}

impl Drag {
    pub(crate) async fn send(&self, hid: &mut impl TouchSender) -> Result<()> {
        let Self {
            x1,
            y1,
            x2,
            y2,
            duration_ms,
            hold_ms,
            end_hold_ms,
        } = *self;
        hid.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, x1, y1)
            .await?;
        tokio::time::sleep(Duration::from_millis(hold_ms)).await;
        let steps = duration_ms.div_ceil(16).max(1) as u32;
        let start = Instant::now();
        let duration = Duration::from_millis(duration_ms);
        let outcome: Result<()> = async {
            for step in 1..=steps {
                let t = step as f64 / steps as f64;
                let x = (x1 as f64 + (x2 as f64 - x1 as f64) * t).round() as u16;
                let y = (y1 as f64 + (y2 as f64 - y1 as f64) * t).round() as u16;
                sleep_until(start + duration * step / steps).await;
                hid.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, x, y)
                    .await?;
            }
            tokio::time::sleep(Duration::from_millis(end_hold_ms)).await;
            Ok(())
        }
        .await;
        let release = hid
            .send_touchscreen(TOUCHSCREEN_STATE_RELEASE, x2, y2)
            .await;
        outcome?;
        release?;
        Ok(())
    }
}

pub(crate) struct Pinch {
    pub x: u16,
    pub y: u16,
    pub start_distance: f64,
    pub end_distance: f64,
    pub angle: f64,
    pub duration_ms: u64,
}

impl Pinch {
    pub(crate) async fn send(&self, hid: &mut impl TouchSender) -> Result<()> {
        let Self {
            x,
            y,
            start_distance,
            end_distance,
            angle,
            duration_ms,
        } = *self;
        let steps = duration_ms.div_ceil(16).max(1) as u32;
        let start = Instant::now();
        let duration = Duration::from_millis(duration_ms);
        let outcome: Result<()> = async {
            for step in 0..=steps {
                sleep_until(start + duration * step / steps).await;
                let distance =
                    start_distance + (end_distance - start_distance) * step as f64 / steps as f64;
                hid.send_multitouch(&pinch_contacts(x, y, distance, angle, true)?)
                    .await?;
            }
            Ok(())
        }
        .await;
        let release = hid
            .send_multitouch(&pinch_contacts(x, y, end_distance, angle, false)?)
            .await;
        outcome?;
        release?;
        Ok(())
    }
}

pub(crate) fn pinch_contacts(
    x: u16,
    y: u16,
    distance: f64,
    angle: f64,
    touching: bool,
) -> Result<Vec<TouchscreenContact>> {
    if !distance.is_finite() || distance <= 0.0 || !angle.is_finite() {
        return Err("pinch distance must be positive and angle finite".into());
    }
    let dx = angle.to_radians().cos() * distance / 2.0;
    let dy = angle.to_radians().sin() * distance / 2.0;
    let positions = [
        (x as f64 - dx, y as f64 - dy),
        (x as f64 + dx, y as f64 + dy),
    ];
    if positions
        .iter()
        .any(|(x, y)| !(0.0..=65535.0).contains(x) || !(0.0..=65535.0).contains(y))
    {
        return Err("pinch contacts fall outside 0..65535".into());
    }
    Ok(positions
        .iter()
        .enumerate()
        .map(|(i, (x, y))| TouchscreenContact {
            identity: i as u8,
            touching,
            x: x.round() as u16,
            y: y.round() as u16,
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::{Instant, advance};

    #[derive(Debug, PartialEq)]
    struct Contact {
        id: u8,
        touching: bool,
        x: u16,
        y: u16,
    }

    struct Transmission {
        at: Duration,
        contacts: Vec<Contact>,
    }

    struct Transport {
        start: Instant,
        delay: Duration,
        fail_at: Option<usize>,
        transmissions: Vec<Transmission>,
    }

    impl Transport {
        fn new(delay_ms: u64, fail_at: Option<usize>) -> Self {
            Self {
                start: Instant::now(),
                delay: Duration::from_millis(delay_ms),
                fail_at,
                transmissions: Vec::new(),
            }
        }

        async fn transmit(&mut self, contacts: Vec<Contact>) -> Result<()> {
            self.transmissions.push(Transmission {
                at: self.start.elapsed(),
                contacts,
            });
            advance(self.delay).await;
            if self.fail_at == Some(self.transmissions.len() - 1) {
                Err("transport failed".into())
            } else {
                Ok(())
            }
        }
    }

    impl TouchSender for Transport {
        async fn send_touchscreen(&mut self, state: u8, x: u16, y: u16) -> Result<()> {
            self.transmit(vec![Contact {
                id: 0,
                touching: state == TOUCHSCREEN_STATE_CONTACT,
                x,
                y,
            }])
            .await
        }

        async fn send_multitouch(&mut self, contacts: &[TouchscreenContact]) -> Result<()> {
            self.transmit(
                contacts
                    .iter()
                    .map(|c| Contact {
                        id: c.identity,
                        touching: c.touching,
                        x: c.x,
                        y: c.y,
                    })
                    .collect(),
            )
            .await
        }
    }

    #[tokio::test(start_paused = true)]
    async fn gesture_transmissions_keep_deadlines_order_holds_and_error_release() {
        // Fixed expectations describe the transmitted path, independent of interpolation code.
        let mut timing_errors = Vec::new();
        let drag_x = [100, 200, 300, 400, 500, 500];
        let pinch_x = [
            (400, 600),
            (350, 650),
            (300, 700),
            (250, 750),
            (200, 800),
            (200, 800),
        ];
        for (duration_ms, delay_ms, drag_times, pinch_times) in [
            (
                64,
                5,
                [0.0, 41.0, 57.0, 73.0, 89.0, 124.0],
                [0.0, 16.0, 32.0, 48.0, 64.0, 69.0],
            ),
            (
                64,
                25,
                [0.0, 61.0, 86.0, 111.0, 136.0, 191.0],
                [0.0, 25.0, 50.0, 75.0, 100.0, 125.0],
            ),
            (
                50,
                5,
                [0.0, 37.5, 50.0, 62.5, 75.0, 110.0],
                [0.0, 12.5, 25.0, 37.5, 50.0, 55.0],
            ),
        ] {
            for pinch in [false, true] {
                // A failed intermediate packet must stop movement and still attempt release.
                for fail_at in [None, Some(2)] {
                    let mut transport = Transport::new(delay_ms, fail_at);
                    let outcome = if pinch {
                        Pinch {
                            x: 500,
                            y: 500,
                            start_distance: 200.0,
                            end_distance: 600.0,
                            angle: 0.0,
                            duration_ms,
                        }
                        .send(&mut transport)
                        .await
                    } else {
                        Drag {
                            x1: 100,
                            y1: 500,
                            x2: 500,
                            y2: 500,
                            duration_ms,
                            hold_ms: 20,
                            end_hold_ms: 30,
                        }
                        .send(&mut transport)
                        .await
                    };
                    if fail_at.is_some() {
                        assert_eq!(outcome.unwrap_err().to_string(), "transport failed");
                    } else {
                        outcome.unwrap();
                    }
                    let expected_indices: &[usize] = if fail_at.is_some() {
                        &[0, 1, 2, 5]
                    } else {
                        &[0, 1, 2, 3, 4, 5]
                    };
                    assert_eq!(transport.transmissions.len(), expected_indices.len());
                    for (packet, &index) in transport.transmissions.iter().zip(expected_indices) {
                        let touching = index != 5;
                        let expected = if pinch {
                            vec![
                                Contact {
                                    id: 0,
                                    touching,
                                    x: pinch_x[index].0,
                                    y: 500,
                                },
                                Contact {
                                    id: 1,
                                    touching,
                                    x: pinch_x[index].1,
                                    y: 500,
                                },
                            ]
                        } else {
                            vec![Contact {
                                id: 0,
                                touching,
                                x: drag_x[index],
                                y: 500,
                            }]
                        };
                        assert_eq!(packet.contacts, expected);
                        let times = if pinch { pinch_times } else { drag_times };
                        let expected_ms = if fail_at.is_some() && index == 5 {
                            times[2] + delay_ms as f64
                        } else {
                            times[index]
                        };
                        let actual_ms = packet.at.as_secs_f64() * 1000.0;
                        // Tokio's timer rounds deadlines to milliseconds; no wall-clock sleeps.
                        if actual_ms < expected_ms || actual_ms >= expected_ms + 2.0 {
                            timing_errors.push(format!(
                                "pinch={pinch}, duration={duration_ms}, delay={delay_ms}, fail={fail_at:?}, packet={index}: expected {expected_ms} ms, got {actual_ms} ms"
                            ));
                        }
                    }
                }
            }
        }
        assert!(timing_errors.is_empty(), "{}", timing_errors.join("\n"));
    }

    #[tokio::test(start_paused = true)]
    async fn strokes_send_each_point_once_on_schedule_and_lift_between_strokes() {
        let point = |x, y, time_ms| PathPoint { x, y, time_ms };
        let strokes = Strokes(vec![
            vec![
                point(100, 500, 0),
                point(200, 500, 16),
                point(300, 500, 32),
                point(400, 500, 48),
            ],
            vec![point(500, 100, 0), point(500, 200, 20)],
        ]);
        let contact = |touching, x, y| Contact {
            id: 0,
            touching,
            x,
            y,
        };
        let first = [
            contact(true, 100, 500),
            contact(true, 200, 500),
            contact(true, 300, 500),
            contact(true, 400, 500),
            contact(false, 400, 500),
        ];
        let second = [
            contact(true, 500, 100),
            contact(true, 500, 200),
            contact(false, 500, 200),
        ];
        let both: Vec<_> = first.iter().chain(&second).collect();
        let gap = STROKE_GAP_MS as f64;
        // A late send goes out at once and still goes out; the lift gap starts after the release completes.
        for (delay_ms, fail_at, sent, times) in [
            (
                5,
                None,
                both.clone(),
                vec![0.0, 16.0, 32.0, 48.0, 53.0, 58.0 + gap, 78.0 + gap, 83.0 + gap],
            ),
            (
                25,
                None,
                both.clone(),
                vec![0.0, 25.0, 50.0, 75.0, 100.0, 125.0 + gap, 150.0 + gap, 175.0 + gap],
            ),
            (
                5,
                Some(2),
                vec![&first[0], &first[1], &first[2], &contact(false, 300, 500)],
                vec![0.0, 16.0, 32.0, 37.0],
            ),
        ] {
            let mut transport = Transport::new(delay_ms, fail_at);
            let outcome = strokes.send(&mut transport).await;
            if fail_at.is_some() {
                assert_eq!(outcome.unwrap_err().to_string(), "transport failed");
            } else {
                outcome.unwrap();
            }
            let packets: Vec<_> = transport.transmissions.iter().map(|t| &t.contacts[0]).collect();
            assert_eq!(packets, sent, "delay={delay_ms}, fail={fail_at:?}");
            for (packet, expected_ms) in transport.transmissions.iter().zip(&times) {
                let actual_ms = packet.at.as_secs_f64() * 1000.0;
                assert!(
                    actual_ms >= *expected_ms && actual_ms < expected_ms + 2.0,
                    "delay={delay_ms}, fail={fail_at:?}: expected {expected_ms} ms, got {actual_ms} ms"
                );
            }
        }
    }
}
