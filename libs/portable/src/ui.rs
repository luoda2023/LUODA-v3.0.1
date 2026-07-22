use native_windows_gui as nwg;
use nwg::NativeUi;
use std::{
    cell::RefCell,
    ops::Deref,
    rc::Rc,
    sync::atomic::{AtomicUsize, Ordering},
};

static PORTABLE_PROGRESS: AtomicUsize = AtomicUsize::new(4);

const WINDOW_SIZE: (i32, i32) = (360, 132);
const BORDER_COLOR: [u8; 3] = [220, 229, 226];
const SURFACE_COLOR: [u8; 3] = [255, 255, 255];

pub fn set_progress(completed: usize, total: usize) {
    let progress = if total == 0 {
        100
    } else {
        4 + completed.saturating_mul(96) / total
    };
    PORTABLE_PROGRESS.store(progress.min(100), Ordering::Relaxed);
}

#[derive(Default)]
pub struct BasicApp {
    window: nwg::Window,
    border_image: nwg::ImageFrame,
    surface_image: nwg::ImageFrame,
    title_label: nwg::Label,
    status_label: nwg::Label,
    progress_bar: nwg::ProgressBar,
    title_font: nwg::Font,
    status_font: nwg::Font,
    border_layout: nwg::GridLayout,
    surface_layout: nwg::GridLayout,
    timer: nwg::AnimationTimer,
}

impl BasicApp {
    fn exit(&self) {
        self.timer.stop();
        nwg::stop_thread_dispatch();
    }

    fn update_progress(&self) {
        let progress = PORTABLE_PROGRESS.load(Ordering::Relaxed).min(100) as u32;
        self.progress_bar.set_pos(progress);
        self.status_label
            .set_text(&format!("正在启动 LDesk  {}%", progress));
    }

    fn start_timer(&self) {
        self.update_progress();
        self.timer.start();
    }
}

mod basic_app_ui {
    use super::*;
    use nwg::{Event, GridLayoutItem};

    pub struct BasicAppUi {
        inner: Rc<BasicApp>,
        default_handler: RefCell<Vec<nwg::EventHandler>>,
    }

    impl nwg::NativeUi<BasicAppUi> for BasicApp {
        fn build_ui(mut data: BasicApp) -> Result<BasicAppUi, nwg::NwgError> {
            nwg::Font::builder()
                .family("Microsoft YaHei UI")
                .size(16)
                .weight(600)
                .build(&mut data.title_font)?;

            nwg::Font::builder()
                .family("Microsoft YaHei UI")
                .size(12)
                .build(&mut data.status_font)?;

            nwg::Window::builder()
                .flags(nwg::WindowFlags::POPUP | nwg::WindowFlags::VISIBLE)
                .title("LDesk")
                .size(WINDOW_SIZE)
                .center(true)
                .build(&mut data.window)?;

            nwg::ImageFrame::builder()
                .parent(&data.window)
                .size(WINDOW_SIZE)
                .background_color(Some(BORDER_COLOR))
                .build(&mut data.border_image)?;

            nwg::ImageFrame::builder()
                .parent(&data.border_image)
                .size((WINDOW_SIZE.0 - 2, WINDOW_SIZE.1 - 2))
                .background_color(Some(SURFACE_COLOR))
                .build(&mut data.surface_image)?;

            nwg::Label::builder()
                .parent(&data.surface_image)
                .text("LDesk")
                .position((24, 18))
                .size((310, 28))
                .font(Some(&data.title_font))
                .background_color(Some(SURFACE_COLOR))
                .build(&mut data.title_label)?;

            nwg::Label::builder()
                .parent(&data.surface_image)
                .text("正在启动 LDesk  4%")
                .position((24, 50))
                .size((310, 22))
                .font(Some(&data.status_font))
                .background_color(Some(SURFACE_COLOR))
                .build(&mut data.status_label)?;

            nwg::ProgressBar::builder()
                .parent(&data.surface_image)
                .position((24, 86))
                .size((310, 9))
                .flags(nwg::ProgressBarFlags::VISIBLE)
                .state(nwg::ProgressBarState::Normal)
                .range(0..100)
                .pos(4)
                .build(&mut data.progress_bar)?;

            nwg::AnimationTimer::builder()
                .parent(&data.window)
                .interval(std::time::Duration::from_millis(50))
                .build(&mut data.timer)?;

            let ui = BasicAppUi {
                inner: Rc::new(data),
                default_handler: Default::default(),
            };

            nwg::GridLayout::builder()
                .parent(&ui.window)
                .spacing(0)
                .margin([0, 0, 0, 0])
                .max_column(Some(1))
                .max_row(Some(1))
                .child_item(GridLayoutItem::new(&ui.border_image, 0, 0, 1, 1))
                .build(&ui.border_layout)?;

            nwg::GridLayout::builder()
                .parent(&ui.border_image)
                .spacing(0)
                .margin([1, 1, 1, 1])
                .max_column(Some(1))
                .max_row(Some(1))
                .child_item(GridLayoutItem::new(&ui.surface_image, 0, 0, 1, 1))
                .build(&ui.surface_layout)?;

            let event_ui = Rc::downgrade(&ui.inner);
            let handle_events = move |event, _event_data, _handle| {
                if let Some(event_ui) = event_ui.upgrade().as_mut() {
                    match event {
                        Event::OnWindowClose => event_ui.exit(),
                        Event::OnTimerTick => event_ui.update_progress(),
                        _ => {}
                    }
                }
            };

            ui.default_handler
                .borrow_mut()
                .push(nwg::full_bind_event_handler(
                    &ui.window.handle,
                    handle_events,
                ));

            Ok(ui)
        }
    }

    impl Drop for BasicAppUi {
        fn drop(&mut self) {
            let mut handlers = self.default_handler.borrow_mut();
            for handler in handlers.drain(..) {
                nwg::unbind_event_handler(&handler);
            }
        }
    }

    impl Deref for BasicAppUi {
        type Target = BasicApp;

        fn deref(&self) -> &BasicApp {
            &self.inner
        }
    }
}

fn ui() -> Result<(), nwg::NwgError> {
    nwg::init()?;
    let app = BasicApp::build_ui(Default::default())?;
    app.start_timer();
    nwg::dispatch_thread_events();
    Ok(())
}

pub fn setup() {
    std::thread::spawn(move || {
        if let Err(error) = ui() {
            eprintln!("{error:?}");
        }
    });
}
