"""VitalServer monitor type wire contract.

The ids are `.vital` TRACKINFO `montype` values and the names are realtime
`send_data` values. Keep this table aligned with the vendored VitalServer
`vitalserver-old/service/include/vitaldb.js` `montypes` contract.
"""

from enum import IntEnum
from typing import Self


class VitalServerMonitorType(IntEnum):
    """Known VitalServer `.vital` and realtime monitor type identifiers."""

    ECG_WAV = 1
    ECG_HR = 2
    ECG_PVC = 3
    IABP_WAV = 4
    IABP_SBP = 5
    IABP_DBP = 6
    IABP_MBP = 7
    PLETH_WAV = 8
    PLETH_HR = 9
    PLETH_SPO2 = 10
    RESP_WAV = 11
    RESP_RR = 12
    CO2_WAV = 13
    CO2_RR = 14
    CO2_CONC = 15
    NIBP_SBP = 16
    NIBP_DBP = 17
    NIBP_MBP = 18
    BT = 19
    CVP_WAV = 20
    CVP_CVP = 21
    EEG_BIS = 22
    TV = 23
    MV = 24
    PIP = 25
    AGENT1_NAME = 26
    AGENT1_CONC = 27
    AGENT2_NAME = 28
    AGENT2_CONC = 29
    DRUG1_NAME = 30
    DRUG1_CE = 31
    DRUG2_NAME = 32
    DRUG2_CE = 33
    CO = 34
    EEG_SEF = 36
    PEEP = 38
    ECG_ST = 39
    AGENT3_NAME = 40
    AGENT3_CONC = 41
    STO2_L = 42
    STO2_R = 43
    EEG_WAV = 44
    FLUID_RATE = 45
    FLUID_TOTAL = 46
    SVV = 47
    DRUG3_NAME = 49
    DRUG3_CE = 50
    FILT1_1 = 52
    FILT1_2 = 53
    FILT2_1 = 54
    FILT2_2 = 55
    FILT3_1 = 56
    FILT3_2 = 57
    FILT4_1 = 58
    FILT4_2 = 59
    FILT5_1 = 60
    FILT5_2 = 61
    FILT6_1 = 62
    FILT6_2 = 63
    FILT7_1 = 64
    FILT7_2 = 65
    FILT8_1 = 66
    FILT8_2 = 67
    PSI = 70
    PVI = 71
    SPHB = 72
    ORI = 73
    ASKNA = 75
    PAP_SBP = 76
    PAP_MBP = 77
    PAP_DBP = 78
    FEM_SBP = 79
    FEM_MBP = 80
    FEM_DBP = 81
    EEG_SEFL = 82
    EEG_SEFR = 83
    EEG_SR = 84
    TOF_RATIO = 85
    TOF_CNT = 86
    SKNA_WAV = 87
    ICP = 88
    CPP = 89
    ICP_WAV = 90
    PAP_WAV = 91
    FEM_WAV = 92
    ALARM_LEVEL = 93
    EEGL_WAV = 95
    EEGR_WAV = 96
    ANII = 97
    ANIM = 98
    PTC_CNT = 99

    @classmethod
    def from_id(cls, value: int) -> Self | None:
        """Return a known member for a wire id, preserving unknown as absent."""

        try:
            return cls(value)
        except ValueError:
            return None

    @classmethod
    def from_wire_name(cls, value: str) -> Self | None:
        """Return a known member for a realtime wire name."""

        return cls.__members__.get(value)
