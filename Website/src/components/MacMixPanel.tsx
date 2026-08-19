import { useState, type CSSProperties, type ReactNode } from "react";
import { IoChevronDown, IoRefresh } from "react-icons/io5";
import { SmoothCorner } from "./SmoothCorner";
import { ThemeImage } from "./ThemeImage";
import { publicUrl } from "../lib/sitePaths";

type DeviceId = "macbook" | "airpods" | "earpods";

type DeviceVolumes = Record<DeviceId, number>;

const INITIAL_OUTPUT_VOLUMES: DeviceVolumes = {
  airpods: 19,
  earpods: 12,
  macbook: 72,
};

const INITIAL_INPUT_VOLUMES: DeviceVolumes = {
  airpods: 67,
  earpods: 84,
  macbook: 72,
};

type MacMixPanelProps = {
  systemVolume: number;
  musicVolume: number;
  safariVolume: number;
  musicMuted: boolean;
  safariMuted: boolean;
  onSystemVolumeChange: (value: number) => void;
  onMusicVolumeChange: (value: number) => void;
  onSafariVolumeChange: (value: number) => void;
  onMusicMuteToggle: () => void;
  onSafariMuteToggle: () => void;
};

type VolumeSliderProps = {
  label: string;
  value: number;
  onChange: (value: number) => void;
  max?: number;
  muted?: boolean;
  showUnityTick?: boolean;
};

const sliderStyle = (value: number, max: number, muted: boolean) =>
  ({
    "--macmix-range-progress": `${(value / max) * 100}%`,
    "--macmix-range-accent": muted
      ? "#8e8e93"
      : value > 100
        ? "#f4c430"
        : "#0a84ff",
  }) as CSSProperties;

function VolumeSlider({
  label,
  value,
  onChange,
  max = 100,
  muted = false,
  showUnityTick = false,
}: VolumeSliderProps) {
  return (
    <span className="macmix-panel__slider-shell">
      <input
        className="macmix-panel__range"
        style={sliderStyle(value, max, muted)}
        type="range"
        min="0"
        max={max}
        step="1"
        value={value}
        onInput={(event) => onChange(Number(event.currentTarget.value))}
        onChange={(event) => onChange(Number(event.currentTarget.value))}
        aria-label={label}
      />
      {showUnityTick ? (
        <span className="macmix-panel__unity-tick" aria-hidden="true" />
      ) : null}
    </span>
  );
}

type DeviceRowProps = {
  icon: string;
  label: string;
  selected: boolean;
  value: number;
  onSelect: () => void;
};

function DeviceRow({
  icon,
  label,
  selected,
  value,
  onSelect,
}: DeviceRowProps) {
  return (
    <button
      className={`macmix-panel__device ${
        selected ? "macmix-panel__device--selected" : ""
      }`.trim()}
      type="button"
      onClick={onSelect}
      aria-pressed={selected}
    >
      <span className="macmix-panel__device-icon" aria-hidden="true">
        <img src={publicUrl(icon)} alt="" />
      </span>
      <span className="macmix-panel__device-name">{label}</span>
      <span className="macmix-panel__percentage">{value}%</span>
    </button>
  );
}

type CollapsibleSectionProps = {
  title: string;
  open: boolean;
  onToggle: () => void;
  children: ReactNode;
};

function CollapsibleSection({
  title,
  open,
  onToggle,
  children,
}: CollapsibleSectionProps) {
  return (
    <section className="macmix-panel__section">
      <button
        className="macmix-panel__section-toggle"
        type="button"
        onClick={onToggle}
        aria-expanded={open}
      >
        <span>{title}</span>
        <IoChevronDown aria-hidden="true" />
      </button>
      <div
        className={`macmix-panel__collapse ${
          open ? "macmix-panel__collapse--open" : ""
        }`.trim()}
      >
        <div className="macmix-panel__collapse-inner">{children}</div>
      </div>
    </section>
  );
}

type MixRowProps = {
  icon: string;
  darkIcon: string;
  name: string;
  value: number;
  muted: boolean;
  onChange: (value: number) => void;
  onMuteToggle: () => void;
};

function MixRow({
  icon,
  darkIcon,
  name,
  value,
  muted,
  onChange,
  onMuteToggle,
}: MixRowProps) {
  return (
    <div className="macmix-panel__mix-row">
      <button
        className={`macmix-panel__app-icon ${
          muted ? "macmix-panel__app-icon--muted" : ""
        }`.trim()}
        type="button"
        onClick={onMuteToggle}
        aria-label={muted ? `Unmute ${name}` : `Mute ${name}`}
      >
        <ThemeImage
          lightSrc={icon}
          darkSrc={darkIcon}
          alt=""
          aria-hidden="true"
        />
        <img
          className="macmix-panel__app-mute-badge"
          src={publicUrl("/assets/MacMix/svgs/speaker.slash.fill.svg")}
          alt=""
          aria-hidden="true"
        />
      </button>
      <span className="macmix-panel__mix-name">{name}</span>
      <VolumeSlider
        label={`${name} volume`}
        value={value}
        max={200}
        onChange={onChange}
        muted={muted}
        showUnityTick
      />
      <button
        className="macmix-panel__restore"
        type="button"
        onClick={() => onChange(100)}
        aria-label={`Restore ${name} volume to 100%`}
      >
        <span>{value}%</span>
        <IoRefresh aria-hidden="true" />
      </button>
    </div>
  );
}

export function MacMixPanel({
  systemVolume,
  musicVolume,
  safariVolume,
  musicMuted,
  safariMuted,
  onSystemVolumeChange,
  onMusicVolumeChange,
  onSafariVolumeChange,
  onMusicMuteToggle,
  onSafariMuteToggle,
}: MacMixPanelProps) {
  const [outputOpen, setOutputOpen] = useState(true);
  const [inputOpen, setInputOpen] = useState(true);
  const [outputDevice, setOutputDevice] = useState<DeviceId>("macbook");
  const [inputDevice, setInputDevice] = useState<DeviceId>("macbook");
  const [outputVolumes, setOutputVolumes] = useState<DeviceVolumes>(() => ({
    ...INITIAL_OUTPUT_VOLUMES,
    macbook: systemVolume,
  }));
  const [inputVolumes, setInputVolumes] = useState<DeviceVolumes>(
    INITIAL_INPUT_VOLUMES,
  );
  const [lastAudibleOutputVolumes, setLastAudibleOutputVolumes] =
    useState<DeviceVolumes>(() => ({
      ...INITIAL_OUTPUT_VOLUMES,
      macbook: systemVolume || INITIAL_OUTPUT_VOLUMES.macbook,
    }));

  const updateSystemVolume = (value: number) => {
    setOutputVolumes((current) => ({
      ...current,
      [outputDevice]: value,
    }));
    if (value > 0) {
      setLastAudibleOutputVolumes((current) => ({
        ...current,
        [outputDevice]: value,
      }));
    }
    onSystemVolumeChange(value);
  };

  const toggleMute = () => {
    updateSystemVolume(
      systemVolume === 0 ? lastAudibleOutputVolumes[outputDevice] : 0,
    );
  };

  const selectOutputDevice = (device: DeviceId) => {
    setOutputDevice(device);
    onSystemVolumeChange(outputVolumes[device]);
  };

  const updateInputVolume = (value: number) => {
    setInputVolumes((current) => ({
      ...current,
      [inputDevice]: value,
    }));
  };

  return (
    <SmoothCorner
      className="macmix-panel"
      radius={20}
      outlineColor="rgba(255, 255, 255, 0.34)"
      outlineWidth={1}
      aria-label="MacMix volume controls"
    >
      <section className="macmix-panel__system">
        <h3>System Volume</h3>
        <div className="macmix-panel__volume-row">
          <button
            className={`macmix-panel__symbol-button ${
              systemVolume === 0 ? "macmix-panel__symbol-button--muted" : ""
            }`.trim()}
            type="button"
            onClick={toggleMute}
            aria-label={systemVolume === 0 ? "Unmute" : "Mute"}
          >
            <img
              className={`speaker-glyph speaker-glyph--${
                systemVolume === 0 ? "slash" : "base"
              }`}
              src={publicUrl(
                `/assets/MacMix/svgs/${
                  systemVolume === 0
                    ? "speaker.slash.fill.svg"
                    : "speaker.fill.svg"
                }`,
              )}
              alt=""
              aria-hidden="true"
            />
          </button>
          <VolumeSlider
            label="System volume"
            value={systemVolume}
            onChange={updateSystemVolume}
            muted={systemVolume === 0}
          />
          <span className="macmix-panel__slider-symbol" aria-hidden="true">
            <img
              className="speaker-glyph speaker-glyph--wave-3"
              src={publicUrl("/assets/MacMix/svgs/speaker.wave.3.fill.svg")}
              alt=""
            />
          </span>
          <output className="macmix-panel__percentage">{systemVolume}%</output>
        </div>
      </section>

      <div className="macmix-panel__divider" />

      <CollapsibleSection
        title="Output"
        open={outputOpen}
        onToggle={() => setOutputOpen((current) => !current)}
      >
        <div className="macmix-panel__devices">
          <DeviceRow
            icon="/assets/MacMix/svgs/airpods.pro.svg"
            label="AirPods Pro"
            selected={outputDevice === "airpods"}
            value={outputVolumes.airpods}
            onSelect={() => selectOutputDevice("airpods")}
          />
          <DeviceRow
            icon="/assets/MacMix/svgs/earpods.svg"
            label="EarPods"
            selected={outputDevice === "earpods"}
            value={outputVolumes.earpods}
            onSelect={() => selectOutputDevice("earpods")}
          />
          <DeviceRow
            icon="/assets/MacMix/svgs/macbook.svg"
            label="MacBook Pro"
            selected={outputDevice === "macbook"}
            value={outputVolumes.macbook}
            onSelect={() => selectOutputDevice("macbook")}
          />
        </div>

        <div className="macmix-panel__mix">
          <h3>Mix</h3>
          <div className="macmix-panel__mix-list">
            <MixRow
              icon="/assets/MacMix/Music-iOS-Default-32@2x.png"
              darkIcon="/assets/MacMix/Music-iOS-Dark-32@2x.png"
              name="Music"
              value={musicVolume}
              muted={musicMuted}
              onChange={onMusicVolumeChange}
              onMuteToggle={onMusicMuteToggle}
            />
            <MixRow
              icon="/assets/MacMix/Safari-iOS-Default-32@2x.png"
              darkIcon="/assets/MacMix/Safari-iOS-Dark-32@2x.png"
              name="Safari"
              value={safariVolume}
              muted={safariMuted}
              onChange={onSafariVolumeChange}
              onMuteToggle={onSafariMuteToggle}
            />
          </div>
        </div>
      </CollapsibleSection>

      <div className="macmix-panel__divider" />

      <CollapsibleSection
        title="Input"
        open={inputOpen}
        onToggle={() => setInputOpen((current) => !current)}
      >
        <div className="macmix-panel__devices">
          <DeviceRow
            icon="/assets/MacMix/svgs/microphone.fill.svg"
            label="AirPods Pro"
            selected={inputDevice === "airpods"}
            value={inputVolumes.airpods}
            onSelect={() => setInputDevice("airpods")}
          />
          <DeviceRow
            icon="/assets/MacMix/svgs/microphone.fill.svg"
            label="EarPods"
            selected={inputDevice === "earpods"}
            value={inputVolumes.earpods}
            onSelect={() => setInputDevice("earpods")}
          />
          <DeviceRow
            icon="/assets/MacMix/svgs/microphone.fill.svg"
            label="MacBook Pro"
            selected={inputDevice === "macbook"}
            value={inputVolumes.macbook}
            onSelect={() => setInputDevice("macbook")}
          />
        </div>

        <div className="macmix-panel__volume-row macmix-panel__input-volume">
          <span className="macmix-panel__slider-symbol" aria-hidden="true">
            <img
              src={publicUrl("/assets/MacMix/svgs/microphone.fill.svg")}
              alt=""
            />
          </span>
          <VolumeSlider
            label="Input gain"
            value={inputVolumes[inputDevice]}
            onChange={updateInputVolume}
          />
          <span className="macmix-panel__slider-symbol" aria-hidden="true">
            <img
              src={publicUrl(
                "/assets/MacMix/svgs/microphone.and.signal.meter.fill.svg",
              )}
              alt=""
            />
          </span>
        </div>
      </CollapsibleSection>
    </SmoothCorner>
  );
}
