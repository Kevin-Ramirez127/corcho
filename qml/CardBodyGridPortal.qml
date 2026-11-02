import QtQuick

CardFrame {
    id: root

    property string targetGridId: (card.targetGridId) || ""
    property var grids: {
        try { return JSON.parse(root.app.gridsJson); } catch (e) { return []; }
    }
    property var target: {
        for (var i = 0; i < grids.length; i++)
            if (grids[i].id === targetGridId) return grids[i];
        return null;
    }

    Column {
        anchors.fill: parent
        spacing: 10

        SelectField {
            width: parent.width
            th: root.th
            value: root.targetGridId
            placeholder: "Select a grid"
            options: root.grids.filter(function (g) { return g.id !== root.gridId; })
                .map(function (g) { return { value: g.id, label: g.name }; })
            onSelected: function (value) {
                root.targetGridId = value;
                root.commit({ targetGridId: value });
            }
        }

        Row {
            spacing: 8

            AppButton {
                th: root.th
                icon: "arrow-right"
                text: root.target ? root.target.name : "Open"
                variant: "solid"
                enabledButton: root.target !== null
                onClicked: root.app.switchGrid(root.targetGridId)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.target ? (root.target.cards.length + " cards") : ""
                color: root.th.muted
                font.family: root.th.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
