"""Make the exported iOS launch storyboard a blank canvas matching Lexerly's thank-you."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

NAVY = ("0.03137255", "0.05098039", "0.10588235")


def stage(path: Path) -> None:
    if path.name != "Launch Screen.storyboard":
        raise ValueError("Provide the generated iOS Launch Screen.storyboard explicitly")
    tree = ET.parse(path)
    root = tree.getroot()
    view = root.find(".//view[@key='view']")
    color = view.find("./color[@key='backgroundColor']") if view is not None else None
    if root.get("launchScreen") != "YES" or view is None or color is None:
        raise ValueError("Unexpected launch storyboard template")
    subviews = view.find("subviews")
    if subviews is not None:
        ids = set()
        for image in subviews.findall("./imageView[@image='SplashImage']"):
            ids.add(image.get("id"))
            subviews.remove(image)
        if len(subviews) == 0:
            view.remove(subviews)
        constraints = view.find("constraints")
        if constraints is not None:
            for item in list(constraints):
                if ids.intersection((item.get("firstItem"), item.get("secondItem"))):
                    constraints.remove(item)
            if len(constraints) == 0:
                view.remove(constraints)
    resources = root.find("resources")
    if resources is not None:
        for item in resources.findall("./image[@name='SplashImage']"):
            resources.remove(item)
        if len(resources) == 0:
            root.remove(resources)
    color.attrib.update(dict(zip(("red","green","blue"),NAVY)))
    if root.findall(".//imageView") or "SplashImage" in ET.tostring(root, encoding="unicode"):
        raise ValueError("The launch storyboard still references an image")
    ET.indent(tree,space="    ")
    tree.write(path,encoding="UTF-8",xml_declaration=True)
    print("Verified logo-free, dark navy iOS launch storyboard.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("storyboard",type=Path)
    stage(parser.parse_args().storyboard)
